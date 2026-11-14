package classeur

// The views (gui_toolkit's views): the sidebar and the inspector, panels docked at the left and the right of the window,
// and the dialogs. The user floats each one, opens it in a window of its own or docks it elsewhere; the toolkit keeps
// that choice, a panel's width and whether it was open in <state>/classeur/views.txt.

import "core:strings"
import "gt:host"
import "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import "gt:ui"

SIDEBAR_VIEW   :: "sidebar"
INSPECTOR_VIEW :: "inspector"
GOTO_VIEW      :: "goto"
OPTIONS_VIEW   :: "options"
CONFLICT_VIEW  :: "conflict"
BATCH_VIEW     :: "batch"
RECORDER_VIEW  :: "recorder"
// The ready-made views of the toolkit that classeur opens.
CONFIRM_DELETE_VIEW :: "confirm_delete"
LAYOUT_NAME_VIEW    :: "layout_name"

// The panels' widths when first docked, and the least ones (ems).
SIDEBAR_EM       :: 15
SIDEBAR_MIN_EM   :: 11
INSPECTOR_EM     :: 27
INSPECTOR_MIN_EM :: 16

// Where the views' memory is: beside the tests' session file for theirs; none (memory only) when headless or for a
// window of a torn-off tab (two processes would write one file).
@(private = "file")
views_file :: proc(app: ^App) -> string {
	if app.session_path != "" { return strings.concatenate({app.session_path, ".views"}, context.temp_allocator) }
	if app.headless || app.standalone { return "" }
	return strings.concatenate({platform.user_dir(.State, APP_NAME, context.temp_allocator), "/views.txt"}, context.temp_allocator)
}

// Once the window is made, before anything opens a view: the memory read, every view declared, the sidebar and the
// inspector open again as they were.
views_start :: proc(app: ^App) {
	h := &app.main
	ui.views_init(&app.views, {path = views_file(app)})
	ui.set_views(&h.state, &app.views)
	ui.views_set_windows(&app.views, host.view_windows(h.shared))
	vs := &app.views
	ui.view_register(vs, SIDEBAR_VIEW, sidebar_view, ui.View_Options{title = i18n.later("Sidebar"), icon = lucide.PANEL_LEFT,
		home = .Panel, home_place = {edge = .Left}, extent_em = SIDEBAR_EM, width_em = SIDEBAR_EM, min_width_em = SIDEBAR_MIN_EM})
	ui.view_register(vs, INSPECTOR_VIEW, inspector_view, ui.View_Options{title = i18n.later("Inspector"), icon = lucide.INFO,
		home = .Panel, home_place = {edge = .Right}, extent_em = INSPECTOR_EM, width_em = INSPECTOR_EM, min_width_em = INSPECTOR_MIN_EM})
	goto_register(app)
	options_register(app)
	conflict_register(app)
	batch_register(app)
	recorder_register(app)
	// (as they were at the last quit; the sidebar open at the very first start)
	_ = ui.view_restore(vs, SIDEBAR_VIEW, app, first_start_open = true, owner = &h.state)
	_ = ui.view_restore(vs, INSPECTOR_VIEW, app, owner = &h.state)
}

sidebar_shown :: proc(app: ^App) -> bool { return ui.view_is_open(&app.views, SIDEBAR_VIEW) }
inspector_shown :: proc(app: ^App) -> bool { return ui.view_is_open(&app.views, INSPECTOR_VIEW) }

// Opens the view `id` on the App, or closes it when it is open (a command that shows or hides a pane).
view_toggle :: proc(app: ^App, id: string) {
	if ui.view_is_open(&app.views, id) { ui.view_close(&app.views, id) } else { ui.view_open(&app.views, id, app) }
}

// The sidebar's view: it fills its place.
@(private = "file")
sidebar_view :: proc(v: ^ui.View, app: ^App) {
	ui.next({width = ui.fill(), height = ui.fill()})
	sidebar_build(app, ui.font_size())
}

// The focus is in a view other than the sidebar and the inspector (those have their own rule: Keys_At): a dialog that
// floats, is docked or is in a window. The list's keys and the commands that act on rows wait.
focus_in_view :: proc(app: ^App) -> bool {
	id, _, ok := ui.views_focus(&app.views)
	return ok && id != SIDEBAR_VIEW && id != INSPECTOR_VIEW
}
