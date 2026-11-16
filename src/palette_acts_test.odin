package classeur

// The everything palette in classeur (gui_toolkit's src/md/features/everything-palette.md, sections 4 and 5): Shift+Enter
// on a command goes to the button that runs it; a command that asks one value asks it in the palette's form.

import "base:runtime"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"
import "fs"

// The top bar's Sidebar button states its command: Shift+Enter on Sidebar in the palette closes the palette and lights
// that button, and runs nothing.
@(test)
test_palette_goes_to_a_command_s_button :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		wait_read(s)
		testing.expect(t, ui.act_shown("command:sidebar"), "the Sidebar button states its command")
		testing.expect(t, ui.act_shown("command:back"), "the focused panel's Back button states its command")
		shown := sidebar_shown(app)
		session.key(s, .K, {.Ctrl})
		session.type_text(s, ">sidebar")
		palette_ranked(s)
		first := palette_first(app)
		testing.expect(t, first >= 0 && COMMANDS[first].id == "sidebar", "Sidebar first")
		session.key(s, .Return, {.Shift})
		session.wait_until(s, proc(s: ^session.Session) -> bool { return (^App)(s.user).main.state.act_light.key != 0 }, "a button lit")
		testing.expect(t, !ui.palette_is_open(&app.palette.pal), "the palette closed")
		testing.expect_value(t, sidebar_shown(app), shown)
		st := &app.main.state
		lit := st.boxes[st.act_light.key] or_else nil
		testing.expect(t, lit != nil && lit.name == "sidebar", "the Sidebar button lit")
	})
}

// Save layout from the palette: its form asks the name, Enter saves the panels under it; the prompt of its keys does not
// open.
@(test)
test_palette_saves_a_layout_by_its_form :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir, session_at = fs.join(dir, ".session", context.temp_allocator))
		context.allocator = runtime.heap_allocator()
		wait_read(s)
		session.key(s, .K, {.Ctrl})
		session.type_text(s, ">save layout")
		palette_ranked(s)
		first := palette_first(app)
		testing.expect(t, first >= 0 && COMMANDS[first].id == "layout_save", "Save layout first")
		session.key(s, .Return)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return ui.palette_run_level(&(^App)(s.user).palette.pal) == .Form }, "its form")
		session.type_text(s, "Desk")
		session.key(s, .Return)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return len((^App)(s.user).layouts.list) == 1 }, "the layout saved")
		testing.expect_value(t, app.layouts.list[0].name, "Desk")
		testing.expect(t, !ui.view_is_open(&app.views, LAYOUT_NAME_VIEW), "no prompt")
		testing.expect(t, !ui.palette_is_open(&app.palette.pal), "the palette closed")
	})
}

// Open layout from the palette: its form lists the saved layouts, the letters typed choose one, Enter opens it in place
// of the panels shown.
@(test)
test_palette_opens_a_layout_by_its_form :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir, session_at = fs.join(dir, ".session", context.temp_allocator))
		context.allocator = runtime.heap_allocator()
		wait_read(s)
		layout_save(app, "one")
		panel_open(app, fs.join(dir, "Documents", context.temp_allocator))
		wait_read(s)
		layout_save(app, "work")
		for len(app.panels) > 1 { panel_close(app, app.panels[len(app.panels) - 1]) }
		testing.expect_value(t, len(app.panels), 1)
		session.key(s, .K, {.Ctrl})
		session.type_text(s, ">open layout")
		palette_ranked(s)
		first := palette_first(app)
		testing.expect(t, first >= 0 && COMMANDS[first].id == "layout_open", "Open layout first")
		session.key(s, .Return)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return ui.palette_run_level(&(^App)(s.user).palette.pal) == .Form }, "its form")
		session.type_text(s, "work")
		session.frames(s, 1)
		session.key(s, .Return)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return len((^App)(s.user).panels) == 2 }, "the layout opened")
		wait_read(s)
		testing.expect_value(t, panel_tab(app.panels[1]).path, fs.join(dir, "Documents", context.temp_allocator))
		testing.expect(t, !ui.menu_is_open(LAYOUTS_MENU), "no menu")
	})
}
