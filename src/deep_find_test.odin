package classeur

// GoTo and the path field find what is below the current folder at any depth: a file by a few letters of its name, a
// relative path typed whole; a click on the crumbs opens the path field, never a dialog.
// Run with -define:ODIN_TEST_THREADS=1 (one interface at a time).

import "base:runtime"
import "core:testing"
import "gt:testkit/unwatched"
import "gt:testkit/session"
import "gt:ui"
import "fs"

@(private = "file")
DEEP_FIXTURE :: [?]string{
	"packages/", "packages/web/", "packages/web/public/", "packages/web/public/brand/", "packages/web/public/brand/logo.svg",
	"packages/web/src/", "packages/web/src/main.ts", ".git/", ".git/logo.svg", "notes.txt",
}

// Frames until the deep search has answered `query` and its walk is over.
@(private = "file")
wait_deep :: proc(s: ^session.Session) {
	session.wait_until(s, proc(s: ^session.Session) -> bool {
		app := (^App)(s.user)
		d := &app.deep
		return d.index != nil && !d.in_flight && d.rows_for == d.asked && d.asked != "" && d.asked_version == d.index.version && d.index.done
	}, "the deep search answered")
	session.frames(s, 2)
}

@(test)
test_goto_deep :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := DEEP_FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		logo := fs.join(dir, "packages/web/public/brand/logo.svg", context.temp_allocator)

		// a few letters of a name four folders down: that file, and not the one under the hidden .git
		session.key(s, .G, {.Ctrl})
		testing.expect(t, ui.view_is_open(&app.views, GOTO_VIEW))
		session.type_text(s, "logo")
		wait_deep(s)
		found := goto_rows(app, dir, "logo")
		if testing.expect(t, len(found.rows) > 0, "a row for logo") {
			testing.expect_value(t, found.rows[0].path, logo)
			testing.expect(t, !found.rows[0].folder, "a file")
		}
		for r in found.rows { testing.expect(t, r.path != fs.join(dir, ".git/logo.svg", context.temp_allocator), "nothing under .git") }
		session.key(s, .Escape)
		session.frames(s, 2)

		// a relative path typed whole: its file first; Enter opens its folder with the file at the cursor
		session.key(s, .G, {.Ctrl})
		session.type_text(s, "packages/web/public/brand/logo.svg")
		wait_deep(s)
		found = goto_rows(app, dir, "packages/web/public/brand/logo.svg")
		if testing.expect(t, len(found.rows) > 0, "a row for the path") { testing.expect_value(t, found.rows[0].path, logo) }
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, !ui.view_is_open(&app.views, GOTO_VIEW), "GoTo closed")
		testing.expect_value(t, tab.path, fs.join(dir, "packages/web/public/brand", context.temp_allocator))
		e := folder_cursor_entry(&tab.folder)
		testing.expect(t, e != nil && e.name == "logo.svg", "the file at the cursor")
	})
}

// A click on the empty part of the crumbs: the path field, its rows under it; no dialog. Letters find what is below.
@(test)
test_crumbs_click_types_the_path :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := DEEP_FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		crumbs := session.get(s, "crumbs")
		if !testing.expect(t, crumbs != nil, "the crumbs") { return }
		// (its right end: past the last crumb, the empty part)
		session.click_at(s, {crumbs.rect.max.x - 4, (crumbs.rect.min.y + crumbs.rect.max.y) * 0.5})
		session.frames(s, 2)
		testing.expect(t, tab.address_open, "the path field")
		testing.expect(t, !ui.view_is_open(&app.views, GOTO_VIEW), "no GoTo dialog")
		session.type_text(s, "main")
		wait_deep(s)
		session.wait_box(s, "sugg0")
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, tab.path, fs.join(dir, "packages/web/src", context.temp_allocator))
	})
}
