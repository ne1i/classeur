package classeur

// The thumbnails of the grid. The cache is the toolkit's ui.Thumb_Cache (gui_toolkit's src/md/features/thumbnails.md):
// only the cards built ask, the asks leave newest first, THUMB_THREADS at a time, one whose card was not built lately is
// dropped before it is read, the least used go over the budget, a texture is made at its first draw. A thumbnail is
// kept by its file's path, size and date (ui.thumb_key): a file changed gets a new one.
//
// A thumbnail is made by the toolkit's ui.file_thumbnail_make, the local source's rules (a picture gt:image reads
// decoded and reduced, else the system's thumbnail), on classeur's own pool (app.thumb_pool). Classeur's own rule over
// it: the system's cache and thumbnailers are asked only when app.system_thumbs is on (off headless: a test never reads
// nor writes the person's cache).

import "base:runtime"
import "core:strings"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

THUMB_THREADS :: 2
THUMB_PX      :: 256
THUMBS_KEPT   :: 400

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
	rgba, w, h, ok := ui.file_thumbnail_make(job.path, job.side, job.system, runtime.heap_allocator())
	if ok { job.rgba, job.size = rgba, {w, h} }
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
