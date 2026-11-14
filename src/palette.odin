package classeur

// The command palette (Ctrl+K, Ctrl+Shift+P): the toolkit's (ui.Command_Palette), the same in every program of the
// family. classeur gives it its sources (src/md/features/palette.md): its commands (`>`, and in the plain search), the
// settings (`:`), the tabs (`@`) and the folders (`/`, palette_sources.odin); the toolkit adds the views' moves. A few
// letters find a command ("nf": New folder), an alias of one's own too (its tags, and put first when typed whole); Enter
// runs it. Ctrl+Enter records keys of one's own for it (the recorder, below), Alt+Enter makes the letters typed its
// alias: the alternates of the commands source. The palette ranks on a chore and remembers the choices
// (palette_choices.txt in the state folder).
//
// The tables given to the palette and to the sheet are made again only when what they read changes (the keymap, the
// language, a command that can or cannot act), with a new version: the palette compares the version, never the table.

import "core:fmt"
import vmem "core:mem/virtual"
import "core:strings"
import "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"

Palette :: struct {
	pal:       ui.Command_Palette,           // the toolkit's: its field, its sources, its usage memory
	settings:  prefs_page.Palette_Settings,  // the settings source
	tabs:      ui.Palette_Source,            // `@` (palette_sources.odin)
	folders:   ui.Palette_Source,            // `/`
	tabs_sig:  u64,                          // what the tabs source's items were made from (tabs_poll)
	folders_cache: Folders_Cache,            // the last folder the folders source listed (palette_sources.odin)
	recording: int,         // the command whose keys are recorded (-1: none): the recorder's view is open
	chords:    [2]Shortcut, // what was pressed so far
	count:     int,
	sheet:     ui.Shortcuts_Sheet,   // the sheet of the keys (F1)

	// the commands source's table: COMMANDS by group, but Tab 1 to Last tab (the tabs source lists the tabs) and the
	// palette's own command; in table_arena, made again when table_key changes
	table:       []ui.Command,
	order:       []int,      // table index -> COMMANDS index
	line_of:     []int,      // COMMANDS index -> table index (-1: not in the table)
	names:       []string,   // table index -> the command's id (the usage memory's and the choice's)
	keys:        []string,   // table index -> the text of its keys (one's own)
	disabled:    [dynamic]bool,
	table_key:   Table_Key,
	enabled:     u64,        // a bit per gated command that can act, as `disabled` says it
	version:     u64,        // the commands source's: bumped when the table or `disabled` changes
	table_arena: vmem.Arena,
	gated:       [dynamic]int,   // the commands that have an `enabled` (read each frame: few)

	sheet_list:  []ui.Command,  // the sheet's table, kept (in sheet_arena) while sheet_key holds
	sheet_key:   Sheet_Key,
	sheet_arena: vmem.Arena,
}

// What the commands' table reads: when one changes, it is made again.
@(private = "file")
Table_Key :: struct {
	built:    bool,
	keymap:   u64,   // Keymap.version: one's own keys and aliases
	language: u32,   // i18n.version(): the keys' texts are in it
}

@(private = "file")
Sheet_Key :: struct {
	built:    bool,
	keymap:   u64,
	language: u32,   // i18n.version() it was made in
	version:  u64,
}

// (the toolkit's palette is destroyed before the window: app_close)
palette_free :: proc(p: ^Palette) {
	ui.shortcuts_sheet_destroy(&p.sheet)
	vmem.arena_destroy(&p.table_arena)
	vmem.arena_destroy(&p.sheet_arena)
	folders_cache_free(&p.folders_cache)
	delete(p.disabled)
	delete(p.gated)
	p^ = {}
}

// Where the palette's choices are kept: <state>/classeur/palette_choices.txt, beside the tests' session file for
// theirs, none (in memory only) when headless or standalone.
palette_choices_file :: proc(app: ^App) -> string {
	if app.session_path != "" { return strings.concatenate({app.session_path, ".choices"}, context.temp_allocator) }
	if app.headless || app.standalone { return "" }
	return strings.concatenate({platform.user_dir(.State, APP_NAME, context.temp_allocator), "/palette_choices.txt"}, context.temp_allocator)
}

// (once the window's state is made: the usage memory is read on its chores)
palette_start :: proc(app: ^App) {
	p := &app.palette
	p.recording = -1   // (no command's keys recorded: the recorder is shut)
	ui.palette_memory_open(&p.pal, &app.main.state, palette_choices_file(app))
	for c, i in COMMANDS { if c.enabled != nil { append(&p.gated, i) } }
	assert(len(p.gated) <= 64, "Palette.enabled holds a bit per gated command")
	// (the settings' page options read when the source needs them: the updater, the themes shown, as they are then)
	prefs_page.palette_settings_add(&p.pal, &p.settings, &app.prefs, &app.options.page, proc(user: rawptr) -> prefs_page.Page_Options {
		return options_page((^App)(user))
	}, proc(user: rawptr) {
		// (the setting chosen is already alone on its page: prefs_page.show)
		app := (^App)(user)
		ui.view_open(&app.views, OPTIONS_VIEW, app)
	}, app)
	palette_sources_add(app)
}

// The palette (a menu's line; Ctrl+K and Ctrl+Shift+P are the toolkit's: palette_build), `typed` in its field.
palette_open :: proc(app: ^App, typed := "") {
	ui.palette_open(&app.palette.pal, typed)
}

// The groups of the commands, in the palette's order, and the group of each (by its id). (Not rodata: i18n.later marks
// them for the catalogue; tr where they are shown.)
COMMAND_GROUPS := [?]string{i18n.later("Go"), i18n.later("Tabs and panels"), i18n.later("Files"), i18n.later("Selection"), i18n.later("View"), i18n.later("Find"), i18n.later("Program")}

command_group :: proc(id: string) -> int {
	has :: strings.has_prefix
	switch {
	case has(id, "app_"): return 6
	case id == "open" || id == "up" || id == "back" || id == "forward" || id == "home" || id == "goto" || id == "goto_popup" || id == "open_folder" || id == "refresh": return 0
	case has(id, "tab") || has(id, "panel") || id == "open_new_tab" || id == "open_other_panel" || has(id, "layout") || id == "lock": return 1
	case has(id, "select"): return 3
	case has(id, "view") || has(id, "zoom") || has(id, "sort") || has(id, "group") || id == "tree" || id == "hidden" || id == "sidebar" || id == "folders_mixed" || id == "inspector": return 4
	case id == "filter" || id == "flat" || id == "types" || id == "files_only" || id == "folders_only" || id == "every_type": return 5
	case id == "shortcuts" || id == "options" || id == "jobs" || id == "jobs_cancel": return 6
	}
	return 2
}

// The index of a command of COMMANDS.
command_index :: proc(c: ^Command) -> int {
	return int((uintptr(c) - uintptr(&COMMANDS[0])) / size_of(Command))
}

// One of the commands that show the tab of a number (Alt+1 to Alt+9): out of the palette, whose tabs source lists the
// tabs themselves.
tab_pick_command :: proc(id: string) -> bool {
	return id == "tab_last" || (len(id) == 5 && strings.has_prefix(id, "tab_") && id[4] >= '1' && id[4] <= '9')
}

// The commands source's table kept: made again when the keymap or the language changed; `disabled` made again when what
// can act changed (a bit per gated command: three of them). Either bumps the source's version.
@(private = "file")
palette_table_keep :: proc(app: ^App) {
	p := &app.palette
	key := Table_Key{built = true, keymap = app.keymap.version, language = i18n.version()}
	enabled: u64
	for c, bit in p.gated { if COMMANDS[c].enabled(app) { enabled |= 1 << u64(bit) } }
	if key == p.table_key && enabled == p.enabled { return }
	if key != p.table_key {
		p.table_key = key
		vmem.arena_free_all(&p.table_arena)
		a := vmem.arena_allocator(&p.table_arena)
		table := make([dynamic]ui.Command, a)
		order := make([dynamic]int, a)
		names := make([dynamic]string, a)
		keys := make([dynamic]string, a)
		line_of := make([]int, len(COMMANDS), a)
		for &l in line_of { l = -1 }
		for g in 0 ..< len(COMMAND_GROUPS) {
			for &c, i in COMMANDS {
				if command_group(c.id) != g || tab_pick_command(c.id) { continue }
				tags := make([dynamic]string, a)
				append(&tags, ..c.tags)
				for alias, id in app.keymap.aliases { if id == c.id { append(&tags, strings.clone(alias, a)) } }
				line_of[i] = len(table)
				append(&table, ui.Command{label = c.title, group = COMMAND_GROUPS[g], icon = c.icon, keys = c.keys, tags = tags[:]})
				append(&order, i)
				append(&names, c.id)
				append(&keys, strings.clone(command_keys(app, &c), a))
			}
		}
		p.table, p.order, p.names, p.keys, p.line_of = table[:], order[:], names[:], keys[:], line_of
	}
	p.enabled = enabled
	resize(&p.disabled, len(p.order))
	for ci, i in p.order {
		c := &COMMANDS[ci]
		p.disabled[i] = c.enabled != nil && !c.enabled(app)
	}
	p.version += 1
}

// The sheet of the keys (F1): every command that has keys under its group, the person's own keys when they set some (a
// sequence reads "Ctrl+M, T", as the sheet joins a command's two chords).
shortcuts_open :: proc(app: ^App) {
	p := &app.palette
	shortcuts_keep(app)
	ui.shortcuts_sheet_open(&p.sheet, p.sheet_list, version = p.sheet_key.version)
}

// The sheet's table, built again only when the keymap or the language changed; an open sheet is given the new one at
// once (it lists from the arena, which the making empties).
@(private = "file")
shortcuts_keep :: proc(app: ^App) {
	p := &app.palette
	key := Sheet_Key{built = true, keymap = app.keymap.version, language = i18n.version(), version = p.sheet_key.version}
	if key != p.sheet_key {
		key.version += 1
		p.sheet_key = key
		vmem.arena_free_all(&p.sheet_arena)
		a := vmem.arena_allocator(&p.sheet_arena)
		list := make([dynamic]ui.Command, a)
		for g in 0 ..< len(COMMAND_GROUPS) {
			for &c in COMMANDS {
				if command_group(c.id) != g { continue }
				keys := c.keys
				if b, ok := app.keymap.custom[c.id]; ok {
					n := b.chords[1].key == .None ? 1 : 2
					keys = make([]Shortcut, n, a)
					copy(keys, b.chords[:n])
				}
				append(&list, ui.Command{label = c.title, group = COMMAND_GROUPS[g], icon = c.icon, keys = keys})
			}
		}
		p.sheet_list = list[:]
		if ui.shortcuts_sheet_is_open(&p.sheet) { p.sheet.commands, p.sheet.version = p.sheet_list, p.sheet_key.version }
	}
}

// What Ctrl+Enter and Alt+Enter do with a command (the hint row's words; English, translated where they show).
// (not rodata: i18n.later marks them for the catalogue)
@(private = "file")
PALETTE_ALTERNATES := ui.Palette_Alternates{ctrl = i18n.later("Set a key"), alt = i18n.later("Make the letters its alias")}

// Each build, before the page's keys: the commands given (compared by their version), Ctrl+K and Ctrl+Shift+P, the
// choice, the recorder's end, the sheet's table.
palette_build :: proc(app: ^App) {
	p := &app.palette
	if ui.shortcuts_sheet_is_open(&p.sheet) { shortcuts_keep(app) }
	if _, ended := ui.view_ended(&app.views, RECORDER_VIEW); ended { palette_recorder_end(app) }
	palette_table_keep(app)
	// (an alias typed whole puts its command first: one lookup in the aliases, while the palette is open; the query is
	// the palette's, its prefix left out)
	first: Maybe(int)
	if ui.palette_is_open(&p.pal) {
		if a := alias_command(app, p.pal.query); a != nil {
			if line := p.line_of[command_index(a)]; line >= 0 { first = line }
		}
	}
	ui.palette_commands(&p.pal, p.table, p.disabled[:], {names = p.names, keys = p.keys, first = first, version = p.version, alternates = PALETTE_ALTERNATES})
	// (not while the recorder is open: it records any chord, Ctrl+K too, as the window's commands wait)
	if !ui.view_is_open(&app.views, RECORDER_VIEW) { _ = ui.palette_keys(&p.pal) }
	// (the toolkit's sources act in palette_chosen: a setting, a view's move)
	if c, ok := ui.palette_chosen(&p.pal); ok { palette_run(app, c) }
}

// A choice of one of classeur's sources.
@(private = "file")
palette_run :: proc(app: ^App, c: ui.Palette_Choice) {
	p := &app.palette
	if _, is := ui.palette_chosen_command(&p.pal, c); is {
		// (by its id, the answer's: the table may have been made again since it was ranked)
		cmd := command_find(c.id)
		if cmd == nil { return }
		switch c.mods {
		case {.Ctrl}:
			// (the palette comes back as it was once the keys are recorded)
			p.recording, p.count, p.chords = command_index(cmd), 0, {}
			ui.view_open(&app.views, RECORDER_VIEW, app)
		case {.Alt}:
			// (the query it was chosen for, its prefix left out)
			needle := strings.trim_space(c.query)
			if needle != "" {
				keymap_alias(app, needle, cmd.id)
				say(app, i18n.tr("%s: an alias of %s."), needle, i18n.tr(cmd.title))
			}
			palette_open(app, strings.clone(c.query, context.temp_allocator))
		case:
			if t := current_tab(app); t != nil { t.focus_due = .List }
			cmd.run(app)
		}
		return
	}
	if c.source == &p.tabs {
		palette_tab_chosen(app, c.id)
	} else if c.source == &p.folders {
		palette_folder_chosen(app, c.id, c.mods)
	}
}

recorder_register :: proc(app: ^App) {
	ui.view_register(&app.views, RECORDER_VIEW, palette_recorder, ui.View_Options{title = i18n.later("Keys of a command"), icon = lucide.KEYBOARD, icon_font = app.icons})
}

// The recorder: a small view while a command's keys are recorded. What is pressed is taken (two chords for a sequence);
// Enter keeps them, Escape forgets them, Backspace first gives the command its own keys again. Then the palette comes
// back as it was (palette_build, when the view ended, however).
@(private = "file")
palette_recorder :: proc(v: ^ui.View, app: ^App) {
	p := &app.palette
	if p.recording < 0 {
		ui.view_end(v, ui.VIEW_CANCELLED)
		return
	}
	c := &COMMANDS[p.recording]
	em := ui.font_size()
	keep, cancel := false, false
	ui.view_title(v, fmt.tprintf(i18n.tr("Keys for %s"), ui.text_shown(i18n.tr(c.title))))
	// (the command in the header, the keys pressed in the body, then the buttons; an unseen build takes no key)
	{
		hk, ok := ui.key_take()
		if ok && hk.key != .None {
			key, mods := hk.key, hk.mods
			switch {
			case key == .Escape && mods == {}:
				cancel = true
			case key == .Return && mods == {} && p.count > 0:
				keep = true
			case key == .Backspace && mods == {} && p.count == 0:
				keymap_unbind(app, c.id)
				say(app, i18n.tr("%s: its own keys again."), i18n.tr(c.title))
				cancel = true
			case:
				if p.count == 2 { p.count = 0; p.chords = {} }
				p.chords[p.count] = Shortcut{key, mods}
				p.count += 1
			}
		}
		if ui.dialog_body("rec_body") {
			if ui.tags("weak") {
				ui.next({width = ui.fill()})
				ui.paragraph(fmt.tprintf("%s###rec_help", i18n.tr("Press them: two for a sequence. Backspace first gives it its own keys again.")))
			}
			ui.spacer(ui.px(em * 0.8))
			ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.6))})
			if ui.row(.Center, id = "###rec_keys") {
				ui.spacer(ui.fill())
				ui.kbd(p.count == 0 ? i18n.tr("Press the keys…") : binding_text(Binding{p.chords}))
				ui.spacer(ui.fill())
			}
		}
		if ui.dialog_buttons("rec_buttons") {
			ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))})
			if ui.button("rec_cancel", i18n.tr("Cancel")).clicked { cancel = true }
			ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))})
			if ui.button("rec_keep", i18n.tr("Keep (Enter)"), o = {intent = .Primary, disabled = p.count == 0}).clicked { keep = true }
		}
	}
	switch {
	case keep && p.count > 0:
		keymap_bind(app, c.id, Binding{p.chords})
		say(app, "%s: %s.", i18n.tr(c.title), binding_text(Binding{p.chords}))
		ui.view_end(v, 0)
	case cancel:
		ui.view_end(v, ui.VIEW_CANCELLED)
	}
}

// The recorder ended (kept, cancelled, closed): the palette again, its letters kept.
@(private = "file")
palette_recorder_end :: proc(app: ^App) {
	p := &app.palette
	if p.recording < 0 { return }
	p.recording = -1
	palette_open(app, strings.clone(ui.line_edit_string(&p.pal.field), context.temp_allocator))
}

// The command of row `k` of the palette's list as the last ranking made it (the tests; -1: not a command, or none).
palette_row_command :: proc(app: ^App, k: int) -> int {
	p := &app.palette
	src, id, ok := ui.palette_row(&p.pal, k)
	if !ok || src != &p.pal.commands.source { return -1 }
	c := command_find(id)
	return c != nil ? command_index(c) : -1
}

// The command of the palette's first row (the tests, once its ranking came).
palette_first :: proc(app: ^App) -> int { return palette_row_command(app, 0) }
