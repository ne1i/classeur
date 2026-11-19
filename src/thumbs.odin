package classeur

// The thumbnails of the grid. The cache is the toolkit's ui.Thumb_Cache (gui_toolkit's src/md/features/thumbnails.md):
// only the cards built ask, the asks leave newest first, THUMB_THREADS at a time, one whose card was not built lately is
// dropped before it is read, the least used go over the budget, a texture is made at its first draw. A thumbnail is
// kept by its file's path, size and date (ui.thumb_key): a file changed gets a new one.
//
// The work is classeur's, on its own pool (app.thumb_pool), with the rules of the toolkit's local source: a picture
// gt:image reads is decoded and reduced; any other file gets the system's thumbnail (desktop.thumbnail: its cache, else
// its thumbnailer); a large picture's is read from the system's cache first, and kept there once decoded. Classeur's own
// rule over it: the system's thumbnails are asked only when app.system_thumbs is on (off headless: a test never reads
// nor writes the person's cache).

import "base:runtime"
import "core:os"
import "core:strings"
import desktop "gt:desktop"
import img "gt:image"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

THUMB_THREADS   :: 2
THUMB_PX        :: 256
THUMBS_KEPT     :: 400
THUMB_MAX_BYTES :: 64 * 1024 * 1024   // a larger file is not read for its thumbnail
THUMB_CACHED_BYTES :: 2 * 1024 * 1024 // a larger picture's thumbnail is read from, and kept in, the system's cache

// The cache's options: THUMBS_KEPT thumbnails of THUMB_PX at most, the count the limit (the bytes of that many full
// thumbnails), as many asks out as the pool has threads.
thumbs_options :: proc() -> ui.Thumb_Options {
	return {side = THUMB_PX, most_count = THUMBS_KEPT, most_bytes = THUMBS_KEPT * THUMB_PX * THUMB_PX * 4, asks = THUMB_THREADS}
}

// One ask of the cache, carried to the pool and back. Its memory is the heap's: it crosses threads.
@(private = "file")
Thumb_Job :: struct {
	app:    ^App,
	ticket: u64,
	path:   string,   // owned
	side:   int,
	system: bool,     // the system's thumbnails may be asked (app.system_thumbs when it was made)
	rgba:   []u8,     // owned: the answer (nil: none)
	size:   [2]int,
}

// Whether gt:image reads a file of this name, by its extension (the toolkit's local source reads the same).
picture_decodes :: proc(name: string) -> bool {
	ext := fs.extension(name)
	if len(ext) > 4 { return false }
	// (folded on the stack: each card built asks, at each frame)
	buf: [4]u8
	for i in 0 ..< len(ext) { c := ext[i]; buf[i] = c >= 'A' && c <= 'Z' ? c + 32 : c }
	switch string(buf[:len(ext)]) {
	case "png", "jpg", "jpeg", "bmp", "webp", "gif": return true
	}
	return false
}

// The entry has a thumbnail to ask: a picture classeur decodes, or any file when the system's thumbnails are asked (a type
// with no thumbnailer fails once, and its card keeps its icon).
thumb_wanted :: proc(app: ^App, e: ^fs.Entry) -> bool {
	return e.kind == .File && (app.system_thumbs || picture_decodes(e.name))
}

// After the cards of a build: the cache's asks sent, the least used dropped.
thumbs_frame :: proc(app: ^App) { ui.thumb_cache_frame(&app.thumbs, thumb_ask, app) }

// Clear thumbnails (act_app_thumbs_clear): every thumbnail forgotten, at the start of the build after the command, when
// no draw holds an entry any more. The cards shown ask for theirs again.
thumbs_clear_apply :: proc(app: ^App) {
	if !app.thumbs_clear_due { return }
	app.thumbs_clear_due = false
	// (the serial goes on: an answer of an ask sent before the clear must not find an entry asked after it)
	serial := app.thumbs.serial
	ui.thumb_cache_destroy(&app.thumbs)
	ui.thumb_cache_init(&app.thumbs, thumbs_options())
	app.thumbs.serial = serial
}

thumbs_free :: proc(app: ^App) { ui.thumb_cache_destroy(&app.thumbs) }

// The cache's ask: the work on the thumbnails' pool, its answer posted back with its ticket.
@(private = "file")
thumb_ask :: proc(user: rawptr, path: string, side: int, ticket: u64) {
	app := (^App)(user)
	a := runtime.heap_allocator()
	job := new(Thumb_Job, a)
	job^ = {app = app, ticket = ticket, path = strings.clone(path, a), side = side, system = app.system_thumbs}
	tasks.add(&app.thumb_pool, thumb_run, job)
}

@(private = "file")
thumb_run :: proc(data: rawptr) {
	job := (^Thumb_Job)(data)
	defer if !ui.post(&job.app.main.state, thumb_done, job) { thumb_free(job) }
	info, ok := fs.stat(job.path)
	if !ok || info.size <= 0 { return }
	// (a type classeur does not decode, or a picture too large to read here: the system's, if it has a thumbnailer)
	if !picture_decodes(job.path) || info.size > THUMB_MAX_BYTES {
		if job.system { thumb_system(job, cached_only = false) }
		return
	}
	// (a large picture: decoding it again costs more than reading the system's copy)
	large := job.system && info.size > THUMB_CACHED_BYTES
	if large && thumb_system(job, cached_only = true) { return }
	a := runtime.heap_allocator()
	bytes, err := os.read_entire_file(job.path, a)
	if err != nil { return }
	defer delete(bytes, a)
	pic, _, decoded := img.decode(bytes, a)
	if !decoded {
		// (a WebP in a build without its decoder, a picture gt:image cannot read: the system may)
		if job.system { thumb_system(job, cached_only = false) }
		return
	}
	defer delete(pic.pixels, a)
	job.rgba, job.size = picture_fit(pic, job.side, a)
	if large { _ = desktop.thumbnail_store(job.path, job.rgba, job.size.x, job.size.y) }
}

// The picture at most `side` on its longer side, its ratio kept (a smaller one as it is), in `allocator`: a box filter,
// each pixel the mean of what it covers (the fastest reduction, and good enough at a card's size).
picture_fit :: proc(pic: img.Image, side: int, allocator: runtime.Allocator) -> ([]u8, [2]int) {
	w, h := pic.width, pic.height
	if max(w, h) <= side {
		out := make([]u8, len(pic.pixels), allocator)
		copy(out, pic.pixels)
		return out, {w, h}
	}
	k := f32(side) / f32(max(w, h))
	small := img.resize(pic, max(1, int(f32(w) * k + 0.5)), max(1, int(f32(h) * k + 0.5)), .Box, allocator)
	return small.pixels, {small.width, small.height}
}

// The system's thumbnail of the job's file: from its cache only, or made by its thumbnailer on a miss (this worker
// waits for it). False: it has none.
@(private = "file")
thumb_system :: proc(job: ^Thumb_Job, cached_only: bool) -> bool {
	a := runtime.heap_allocator()
	th: desktop.Thumbnail
	ok: bool
	if cached_only {
		th, ok = desktop.thumbnail_cached(job.path, job.side, a)
	} else {
		th, ok = desktop.thumbnail(job.path, job.side, a)
	}
	if !ok { return false }
	job.rgba, job.size = th.rgba, th.size
	return true
}

@(private = "file")
thumb_free :: proc(job: ^Thumb_Job) {
	a := runtime.heap_allocator()
	delete(job.path, a)
	delete(job.rgba, a)
	free(job, a)
}

// The answer, on the interface's thread: the pixels (copied by the cache), or none (the card keeps its icon).
@(private = "file")
thumb_done :: proc(data: rawptr, word: u64) {
	job := (^Thumb_Job)(data)
	defer thumb_free(job)
	app := job.app
	if job.rgba != nil {
		ui.thumb_cache_answer(&app.thumbs, job.ticket, job.rgba, job.size.x, job.size.y)
	} else {
		ui.thumb_cache_failed(&app.thumbs, job.ticket)
	}
	app_frames(app)
}
