package classeur

// The caches of pictures: what is on screen is never let go, a thumbnail scrolled past is not decoded. (A pool whose
// threads are all held by a hung read starts another: gt:tasks' own test.)

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"
import "fs"

@(test)
test_tidy_keeps_shown :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		_, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		// more pictures used in this frame than are kept: none goes
		for _, &ic in app.icons_cache { ic.used = app.frame }
		for i in 0 ..< ICONS_KEPT + 20 {
			app.icons_cache[strings.clone(fmt.tprintf("test:%d@16", i))] = {state = .Failed, used = app.frame}
		}
		icons := len(app.icons_cache)
		icons_tidy(app)
		testing.expect_value(t, len(app.icons_cache), icons)
		// the thumbnails, in a cache of classeur's options: more cards built in this frame than are kept, none goes
		// (answered at once, as failed: an entry waiting or asked is never dropped, so they would prove nothing)
		c: ui.Thumb_Cache
		ui.thumb_cache_init(&c, thumbs_options())
		defer ui.thumb_cache_destroy(&c)
		no_ask :: proc(user: rawptr, path: string, side: int, ticket: u64) {}
		for i in 0 ..< THUMBS_KEPT + 20 {
			th := ui.thumb_cache_get(&c, fmt.tprintf("/test/%d|1|1", i), "/test")
			th.state = .Failed
		}
		clear(&c.waiting)
		ui.thumb_cache_frame(&c, no_ask, nil)
		testing.expect_value(t, len(c.entries), THUMBS_KEPT + 20)
		// none built for long: the oldest go, down to the budget
		c.frame += 100
		ui.thumb_cache_frame(&c, no_ask, nil)
		testing.expect(t, len(c.entries) <= THUMBS_KEPT, "the thumbnails not built for long go")
		// one not used for long goes; those of this frame stay
		app.frame += 100
		for _, &ic in app.icons_cache { ic.used = app.frame }
		old := strings.clone("test:old@16")
		app.icons_cache[old] = {state = .Failed, used = app.frame - 100}
		icons_tidy(app)
		testing.expect(t, "test:old@16" not_in app.icons_cache, "the picture not used for long goes")
		testing.expect_value(t, len(app.icons_cache), icons)
	})
}

@(test)
test_thumb_stale :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		write_pictures(dir, {"a.png"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		path := fs.join(dir, "a.png", context.temp_allocator)
		testing.expect(t, ui.thumb_key(path, 10, 1) != ui.thumb_key(path, 11, 1), "a file changed has a new thumbnail")
		testing.expect(t, ui.thumb_key(path, 10, 1) != ui.thumb_key(path, 10, 2), "a file changed has a new thumbnail")
		session.frames(s, ui.THUMB_STALE_FRAMES + 2)
		testing.expect(t, app.thumbs.frame > ui.THUMB_STALE_FRAMES, "frames built")

		// a card not built for a few frames (the details show none): its picture is not read, and its entry goes (asked
		// again when it comes back)
		key := strings.clone(ui.thumb_key(path, 1, 1), context.temp_allocator)
		stale := ui.thumb_cache_get(&app.thumbs, key, path)
		stale.used = 0
		sent, skipped := app.thumbs.sent, app.thumbs.skipped
		session.frames(s, 1)
		testing.expect_value(t, app.thumbs.skipped, skipped + 1)
		testing.expect_value(t, app.thumbs.sent, sent)
		testing.expect(t, key not_in app.thumbs.entries, "the stale request is put back as not asked")

		// a card built in this frame: its picture is made
		key = strings.clone(ui.thumb_key(path, 2, 2), context.temp_allocator)
		_ = ui.thumb_cache_get(&app.thumbs, key, path)
		session.frames(s, 1)
		testing.expect_value(t, app.thumbs.sent, sent + 1)
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			for _, th in (^App)(s.user).thumbs.entries { if th.state == .Waiting || th.state == .Asked { return false } }
			return true
		}, "the thumbnail")
		th, ok := app.thumbs.entries[key]
		testing.expect(t, ok && th.state == .Ready, "the wanted thumbnail is ready")
	})
}

// A file's icon key is asked on a worker (the toolkit's may read the system's type database): at first none, then the
// worker's answer, kept by the name.
@(test)
test_icon_key_on_a_worker :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		name := "a never seen name.qzx"
		ic, ready, failed := sys_icon(app, fs.join(dir, name, context.temp_allocator), false, 16)
		testing.expect(t, ic == nil && !ready && !failed, "no picture while its key is asked")
		testing.expect(t, name in app.icon_keys && app.icon_keys[name] == "", "asked")
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			k, ok := (^App)(s.user).icon_keys["a never seen name.qzx"]
			return ok && k != ""
		}, "the worker's key")
	})
}
