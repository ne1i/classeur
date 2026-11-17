package classeur

// The session: what the window shows comes back at the next start (File Pilot's): the panels and their tabs (the
// folder, the view's zoom, the lock), the panel with the keyboard; and the bookmarks and the recent folders. (The
// window's place and size are the toolkit's window.placement, settings.odin; the sidebar and the inspector are views: the
// toolkit's memory of the views keeps them, views.odin.) A text file, a line per thing, written when the window closes
// and, on a worker, as soon as any of it changes (session_autosave: a program killed, a session of the system ended,
// loses nothing):
//
//   focus <panel>
//   panel <active tab>
//   tab <zoom> <locked 0|1> <sort key> <descending 0|1> <path>
//   bookmark <path>
//   recent <path>
//
// A line not understood is skipped (a file of another version loses that line only). A tab whose folder is gone opens
// at the nearest folder above it that is still there (the read of the tab goes up: tab.odin's load_done).
//
// It is read at the start by a worker (start_read_ask), never on the interface's thread: a settings' folder on a share
// that does not answer would keep the window from opening. Until it comes the window shows the start's tab.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "gt:platform"
import store "gt:store"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

// Where the session is kept: <config>/FromentSoftware/Classeur/session, unless the tests gave theirs.
session_file :: proc(app: ^App, allocator := context.temp_allocator) -> string {
	if app.session_path != "" { return strings.clone(app.session_path, allocator) }
	if app.headless || app.standalone { return "" }
	return strings.concatenate({platform.user_dir(.Config, APP_FOLDER, context.temp_allocator), "/session"}, allocator)
}

// `later`: written by its writer's thread (the session changed while the window runs); else now, waited for (the window
// closes: whatever was pending is superseded by this one). Nothing while the start's read has not come: the start's
// state written then would replace the last session before it is read.
session_save :: proc(app: ^App, later := false) {
	if app.start_read == .Reading { return }
	path := session_file(app)
	if path == "" { return }
	b := strings.builder_make(context.temp_allocator)
	session_rest(app, &b)
	store.writer_put(&app.session_writer, transmute([]u8)strings.to_string(b))
	if !later { store.writer_flush(&app.session_writer) }
}

// What the session holds but the window's place.
@(private = "file")
session_rest :: proc(app: ^App, b: ^strings.Builder) {
	panels_text(app, b)
	for p in app.bookmarks { fmt.sbprintf(b, "bookmark %s\n", p) }
	for p in app.recents { fmt.sbprintf(b, "recent %s\n", p) }
}

// After a frame: the session written again when what it holds changed and stayed so SESSION_SETTLE_MS (the window's
// place alone waits for the next write: a window moved or resized changes it every frame). Not while a press is held:
// a press that moves something changes it every frame; once let go and settled it is written once.
SESSION_SETTLE_MS :: 400

session_autosave :: proc(app: ^App) {
	// (before the start's read came, session_written would note a text never written: session_save)
	if app.start_read == .Reading || session_file(app) == "" || ui.active_key() != 0 { return }
	b := strings.builder_make(context.temp_allocator)
	session_rest(app, &b)
	text := strings.to_string(b)
	if text == app.session_written {
		app.session_changed_ms = 0
		return
	}
	// (changed: written once it has not changed for a while; the loop is woken then, the window may be idle)
	now := ui.now_ms()
	if text != app.session_seen {
		delete(app.session_seen)
		app.session_seen = strings.clone(text)
		app.session_changed_ms = now
	}
	if left := SESSION_SETTLE_MS - (now - app.session_changed_ms); left > 0 {
		ui.wake_within(&app.main.state, int(left) + 1)   // (the loop sleeps: woken when it is due)
		return
	}
	delete(app.session_written)
	app.session_written = strings.clone(text)
	session_save(app, later = true)
}

// The panels and their tabs as lines (the session's, a layout's).
panels_text :: proc(app: ^App, b: ^strings.Builder) {
	fmt.sbprintf(b, "focus %d\n", app.focus)
	for p in app.panels {
		fmt.sbprintf(b, "panel %d%s\n", p.active, p.below ? " below" : "")
		for t in p.tabs { fmt.sbprintf(b, "tab %d %d %d %d %s\n", t.zoom, t.locked ? 1 : 0, int(t.folder.sort.key), t.folder.sort.descending ? 1 : 0, t.path) }
	}
}

// Opens the panels and tabs that `text`'s focus, panel and tab lines say, after the panels there are (none: the caller
// closed them). True: a panel opened.
panels_open :: proc(app: ^App, text: string) -> bool {
	rest_text := text
	panel: ^Panel
	focus := 0
	first := len(app.panels)
	for line in strings.split_lines_iterator(&rest_text) {
		word, _, rest := strings.partition(line, " ")
		switch word {
		case "focus":
			focus, _ = strconv.parse_int(rest)
		case "panel":
			panel = new(Panel)
			append(&app.panels, panel)
			active_text, _, flags := strings.partition(rest, " ")
			panel.active, _ = strconv.parse_int(active_text)
			panel.below = flags == "below" && len(app.panels) > first + 1
		case "tab":
			if panel == nil { continue }
			parts: [4]string
			dir := rest
			for i in 0 ..< 4 { parts[i], _, dir = strings.partition(dir, " ") }
			if dir == "" { continue }
			zoom, _ := strconv.parse_int(parts[0])
			key, _ := strconv.parse_int(parts[2])
			// (a folder gone since: the read, on a worker, goes up to the nearest one still there)
			tab_open(app, panel, dir)
			t := panel.tabs[len(panel.tabs) - 1]
			t.zoom = clamp(zoom, 0, len(ZOOMS) - 1)
			t.locked = parts[1] == "1"
			if key >= 0 && key <= int(max(fs.Sort_Key)) {
				t.folder.sort.key, t.folder.sort.descending = fs.Sort_Key(key), parts[3] == "1"
			}
		}
	}
	// (a panel left with no tab, a version's file cut short: dropped)
	for i := len(app.panels) - 1; i >= first; i -= 1 {
		if len(app.panels[i].tabs) == 0 {
			panel_destroy(app.panels[i])
			ordered_remove(&app.panels, i)
		}
	}
	for p in app.panels { p.active = clamp(p.active, 0, len(p.tabs) - 1) }
	app.focus = clamp(first + focus, 0, max(len(app.panels) - 1, 0))
	return len(app.panels) > first
}

// The start's read of the session and the layouts (src/md/features/session.md). Reading is the zero value: a new App
// writes neither file until the answer has come.
Start_Read :: enum {
	Reading,   // a worker reads the files: nothing of them is written (session_save, layouts_save)
	Applied,   // the answer was applied: the session's panels, if it had any, in place of the start's
	Dropped,   // the answer came after the person acted: its panels dropped, the person's kept
}

// The session and the layouts as the start's worker read them, on their way to the interface's thread.
@(private = "file")
Start_Read_Job :: struct {
	app:          ^App,
	gate:         ^sync.Sema,        // the tests: waited for before the read
	session_path: string,            // owned ("": none)
	layouts_path: string,            // owned ("": none)
	panels:       string,            // owned: the session's focus, panel and tab lines
	bookmarks:    [dynamic]string,   // owned
	recents:      [dynamic]string,   // owned
	layouts:      [dynamic]Layout,
}

// Asks a worker to read the session and the layouts; the start's panels are shown meanwhile. `folders`: the command
// line's, opened again beside a restored session (their priority over it, as when the read was synchronous).
start_read_ask :: proc(app: ^App, folders: []string) {
	session_path, layouts_path := session_file(app), layouts_file(app)
	if session_path == "" && layouts_path == "" {
		app.start_read = .Applied   // (nothing to read: a test's window with no session file)
		return
	}
	app.start_read = .Reading
	b := strings.builder_make(context.temp_allocator)
	panels_text(app, &b)
	app.start_panels = strings.clone(strings.to_string(b))
	for f in folders { append(&app.start_folders, strings.clone(f)) }
	app.answers_due += 1
	r := new(Start_Read_Job)
	r^ = {app = app, gate = app.start_gate, session_path = strings.clone(session_path), layouts_path = strings.clone(layouts_path)}
	tasks.add(&app.pool, start_read_run, r)
}

@(private = "file")
start_read_run :: proc(data: rawptr) {
	r := (^Start_Read_Job)(data)
	if r.gate != nil { sync.sema_wait(r.gate) }
	if r.session_path != "" {
		if text, err := os.read_entire_file(r.session_path, context.temp_allocator); err == nil { session_parse(r, string(text)) }
	}
	if r.layouts_path != "" {
		if text, err := os.read_entire_file(r.layouts_path, context.temp_allocator); err == nil { r.layouts = layouts_parse(string(text)) }
	}
	if !ui.post(&r.app.main.state, start_read_done, r) { start_read_free(r) }
}

// On the worker: the session's lines sorted out (a line not understood is skipped).
@(private = "file")
session_parse :: proc(r: ^Start_Read_Job, text: string) {
	rest_text := text
	panel_lines := strings.builder_make()
	for line in strings.split_lines_iterator(&rest_text) {
		word, _, rest := strings.partition(line, " ")
		switch word {
		case "focus", "panel", "tab":
			fmt.sbprintf(&panel_lines, "%s\n", line)
		case "bookmark":
			if rest != "" { append(&r.bookmarks, strings.clone(rest)) }
		case "recent":
			if rest != "" && len(r.recents) < RECENTS_MAX { append(&r.recents, strings.clone(rest)) }
		}
	}
	r.panels = strings.to_string(panel_lines)
}

// On the interface's thread: the session's panels in place of the start's, unless the person acted first (then theirs
// stay: a tab they opened must not vanish under them); the bookmarks, the recents and the layouts merged either way.
@(private = "file")
start_read_done :: proc(data: rawptr, word: u64) {
	r := (^Start_Read_Job)(data)
	app := r.app
	defer start_read_free(r)
	app.answers_due -= 1
	app.start_read = .Applied
	if r.panels != "" {
		b := strings.builder_make(context.temp_allocator)
		panels_text(app, &b)
		if app.start_acted || strings.to_string(b) != app.start_panels {
			app.start_read = .Dropped
		} else {
			start_panels_replace(app, r.panels)
		}
	}
	// (the file's bookmarks first, then those added since the start)
	bookmarks := r.bookmarks
	r.bookmarks = {}
	for p in app.bookmarks {
		if slice.contains(bookmarks[:], p) { delete(p) } else { append(&bookmarks, p) }
	}
	delete(app.bookmarks)
	app.bookmarks = bookmarks
	// (the folders visited since the start first, as the synchronous read gave: their reads put them in front)
	for p in r.recents {
		if len(app.recents) < RECENTS_MAX && !slice.contains(app.recents[:], p) { append(&app.recents, p) } else { delete(p) }
	}
	clear(&r.recents)
	layouts_merge(app, &r.layouts)   // (after the state: it may write the layouts now)
	start_read_forget(app)
	app_frames(app)
}

// The start's panels destroyed and the session's opened, the command line's folders beside them. A session whose lines
// open no panel leaves the start's.
@(private = "file")
start_panels_replace :: proc(app: ^App, text: string) {
	old, old_focus := app.panels, app.focus
	app.panels = {}
	if !panels_open(app, text) {
		delete(app.panels)
		app.panels, app.focus = old, old_focus
		return
	}
	for p in old { panel_destroy(p) }
	delete(old)
	folders_show(app, app.start_folders[:])
	if t := current_tab(app); t != nil { t.focus_due = .List }
}

// What the start kept for the answer, let go (the answer came, or the window closed first).
start_read_forget :: proc(app: ^App) {
	delete(app.start_panels)
	app.start_panels = ""
	for f in app.start_folders { delete(f) }
	delete(app.start_folders)
	app.start_folders = nil
}

@(private = "file")
start_read_free :: proc(r: ^Start_Read_Job) {
	delete(r.session_path)
	delete(r.layouts_path)
	delete(r.panels)
	for p in r.bookmarks { delete(p) }
	delete(r.bookmarks)
	for p in r.recents { delete(p) }
	delete(r.recents)
	for x in r.layouts { delete(x.name); delete(x.text) }
	delete(r.layouts)
	free(r)
}
