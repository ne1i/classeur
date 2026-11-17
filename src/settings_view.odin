package classeur

// The settings (Ctrl+,): the toolkit's settings page (gt:prefs_page) in a view (views.odin), a dialog over the window at
// home that the person resizes by its edges and corner. Every preference of the registry that is not the program's own has its line there: its title,
// what it does, its control; the search on the left finds them by their words. The themes are cards.

import config "gt:config"
import "gt:i18n"
import lucide "gt:lucide"
import prefs_page "gt:prefs_page"
import "gt:ui"

// Its size when first opened, and the least it can be made (em).
OPTIONS_PREFERRED_EM :: [2]f32{56, 40}
OPTIONS_MIN_EM :: [2]f32{34, 20}

Options :: struct {
	page: prefs_page.Page,
	shown: bool,     // it was open at the last build (closed since: a slider's preview undone)
}

options_free :: proc(o: ^Options) {
	prefs_page.destroy(&o.page)
	o^ = {}
}

options_register :: proc(app: ^App) {
	ui.view_register(&app.views, OPTIONS_VIEW, options_view, ui.View_Options{
		title = i18n.later("Settings"), icon = lucide.SETTINGS, icon_font = app.icons, resizable = true,
		width_em = OPTIONS_PREFERRED_EM.x, height_em = OPTIONS_PREFERRED_EM.y, min_width_em = OPTIONS_MIN_EM.x, min_height_em = OPTIONS_MIN_EM.y,
	})
}

act_options :: proc(app: ^App) {
	if ui.view_is_open(&app.views, OPTIONS_VIEW) {
		ui.view_close(&app.views, OPTIONS_VIEW)
		return
	}
	prefs_page.focus_search(&app.options.page)
	ui.view_open(&app.views, OPTIONS_VIEW, app)
}

// The settings open on the setting `name` alone (the palette's).
options_show :: proc(app: ^App, name: string) {
	ui.view_open(&app.views, OPTIONS_VIEW, app)
	prefs_page.show(&app.options.page, &app.prefs, options_page(app), name)
}

// The pages in their order: the toolkit's standard groups (docs/settings.md) and classeur's own (files, open); General
// first, as in every program of the family, so the settings open on it.
// (not rodata: i18n.later marks the titles for the catalogue; the page translates them where it shows them)
@(private = "file")
OPTIONS_PAGES := [?]prefs_page.Page_Info{
	{category = "general", title = i18n.later("General"), icon = lucide.SETTINGS},
	{category = "appearance", title = i18n.later("Appearance"), icon = lucide.PALETTE},
	{category = "window", title = i18n.later("Window"), icon = lucide.APP_WINDOW},
	{category = "files", title = i18n.later("Files"), icon = lucide.FILE},
	{category = "open", title = i18n.later("Opening"), icon = lucide.FOLDER_OPEN},
	{category = "scrolling", title = i18n.later("Scrolling"), icon = lucide.MOUSE},
	{category = "input", title = i18n.later("Input"), icon = lucide.KEYBOARD},
	{category = "timing", title = i18n.later("Delays and menus"), icon = lucide.TIMER},
	{category = "update", title = i18n.later("Updates"), icon = lucide.DOWNLOAD},
	{category = "rendering", title = i18n.later("Rendering"), icon = lucide.MONITOR},
}

// Each frame: the settings closed, however (their command, Escape, the close cross, the view's menu), while a slider was
// held: what it showed and did not write goes back to the preferences.
options_follow :: proc(app: ^App) {
	o := &app.options
	open := ui.view_is_open(&app.views, OPTIONS_VIEW)
	if !open && o.shown { options_unpreview(app) }
	o.shown = open
}

@(private = "file")
options_view :: proc(v: ^ui.View, app: ^App) {
	o := &app.options
	// (Escape closes it, unless a field of the page has the keyboard: that Escape is the field's)
	if !prefs_page.editing(&o.page) && ui.key_press(.Escape) { ui.view_end(v, ui.VIEW_CANCELLED) }
	ui.next({width = ui.fill(), height = ui.fill()})
	prefs_page.build(&o.page, &app.prefs, options_page(app))
}

// What a held slider showed and did not write, back to the preferences' values.
@(private = "file")
options_unpreview :: proc(app: ^App) {
	ui.set_rounding(&app.main.state, f32(config.float_of(&app.prefs, "appearance.rounding")))
	settings_apply(app)
}

// The build of the README's pictures (classeurtool shots). They are made before a release sets its version: a version
// shown in them would be the last release's.
@(private = "file")
SHOTS_BUILD :: #config(CLASSEUR_SHOTS, false)

// The settings page's options: its build's, and the palette's list of the settings (palette.odin).
options_page :: proc(app: ^App) -> prefs_page.Page_Options {
	return {
		version = SHOTS_BUILD ? "" : APP_TITLE + " " + APP_VERSION,
		user = app,
		pages = OPTIONS_PAGES[:],
		icon_font = app.icons, search_icon = lucide.SEARCH, reset_icon = lucide.ROTATE_CCW,
		file = SHOTS_BUILD ? "" : prefs_path(app),
		changed = proc(user: rawptr, _: string) { settings_apply((^App)(user)) },
		// (a slider held: its value shown at once, written when it is let go; only what moves nothing: a text size
		// shown live moved the slider under the pointer, it comes when let go)
		preview = proc(user: rawptr, name: string, value: f64) {
			app := (^App)(user)
			switch name {
			case "appearance.rounding":         ui.set_rounding(&app.main.state, f32(value))
			case "appearance.inactive_opacity": app.settings.inactive_opacity = f32(value)
			}
			app_frames(app)
		},
		updater = app.updates.updater,
		restart = proc(user: rawptr) { updates_restart((^App)(user)) },
		themes = themes(app), themes_light = app.theme_shown.light, themes_file = &app.themes_file,
		changelog = &app.changelog, licence = &app.licence, install = &app.install, diagnostics = prefs_page.diagnostics_of(&app.main),
	}
}
