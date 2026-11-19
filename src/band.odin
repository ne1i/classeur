package classeur

// The rectangle selection (a rubber band) is the toolkit's ui.Item_Band (gui_toolkit's src/md/features/view-modes.md):
// a press on the empty part of a list, then a drag, selects every row the rectangle touches; with Ctrl the rows are
// added to the selection there was; Ctrl and a press on a row start it from there. Classeur adds what its folder has
// and the toolkit's band does not know: one band for the window (its tab), the folder's menu on the empty part, the
// rows of a folded group left out, and the selection's bytes kept row by row.

import "core:fmt"
import "gt:ui"

Band :: struct {
	using band: ui.Item_Band,
	tab:        u64,   // the tab whose list it runs in
}

// Ctrl and a press on a row: a band from there, its rows taken out of the selection when that row was in it. Called
// before the press toggles the row: the base is the selection there was.
band_begin_on_row :: proc(app: ^App, t: ^Tab, removing: bool) {
	ui.item_band_begin(&app.band.band, band_box(t), &t.folder.selection, removing)
	if app.band.active { app.band.tab = t.id }
}

// The box the items of `t` are laid out in: the columns view's, or the virtual list's.
band_box :: proc(t: ^Tab) -> ^ui.Box {
	if ZOOMS[clamp(t.zoom, 0, len(ZOOMS) - 1)].mode == .Columns { return ui.box_from_key(t.cols_key) }
	return ui.box_from_key(t.vl.key)
}

band_free :: proc(b: ^Band) {
	ui.item_band_destroy(&b.band)
	b^ = {}
}

// After the items of `t`'s list: a band starts, follows the pointer, or ends; a right click on the empty part opens the
// folder's menu. `pressed_row`: an item took the press; `pressed_empty`, `right_empty`: a press, a right click on an
// empty part that is not the box itself (between the grid's cards); `layout`: where the items are (its list: the tab's,
// when nil; a list's rows when it is all zero).
band_update :: proc(app: ^App, t: ^Tab, pressed_row: bool, pressed_empty := false, right_empty := false, layout := ui.Item_Band_Layout{}) {
	f := &t.folder
	box := band_box(t)
	if box == nil { return }
	b := &app.band
	sig := ui.signal(box)
	// (a right click on the empty part: the folder's menu, what makes and pastes)
	if (sig.right_clicked || right_empty) && !pressed_row { entry_menu_open(app, t, ui.mouse_pos(), on_entry = false) }
	// (one band for the window: while it runs in another tab, this one's list starts none and is left as it is)
	if b.active && b.tab != t.id { return }
	layout := layout
	if layout.vl == nil { layout.vl = &t.vl }
	// the selection's bytes follow the rows the band changes (folder_set_row's rule): the rows it held at the last
	// frame, as they were, so that the change is known row by row and not counted again over the whole folder
	was_active, old_lo, old_hi := b.active, b.lo, b.hi
	known := was_active && f.bytes_known && f.bytes_of == f.version
	before: []bool
	if known {
		before = make([]bool, old_hi - old_lo, context.temp_allocator)
		for row in old_lo ..< old_hi { before[row - old_lo] = folder_row_selected(f, row) }
	}
	if !ui.item_band_update(&b.band, &f.selection, folder_rows(f), box, layout, pressed_row, pressed_empty, fmt.tprintf("###band%d", t.id)) { return }
	b.tab = t.id
	if known {
		// (the rows it visited: those of this frame and of the last; a row out of the last frame's was as the base
		// leaves it, which is how the band leaves every row it no longer touches)
		from, to := b.lo, b.hi
		if old_lo != old_hi { from, to = min(old_lo, b.lo), max(old_hi, b.hi) }
		for row in from ..< min(to, len(f.shown)) {
			was := row >= old_lo && row < old_hi ? before[row - old_lo] : b.keeping && f.ids[row] in b.base
			now := folder_row_selected(f, row)
			if was == now { continue }
			bytes := file_bytes(f.listing.entries[f.shown[row]])
			f.sel_bytes += now ? bytes : -bytes
		}
		f.bytes_of = f.version
	}
	// (a folded group's first row is its title: its files are not shown, the rectangle does not take them)
	if f.group != .None && f.filter == "" && len(f.folded) > 0 {
		for row in b.lo ..< min(b.hi, len(f.shown)) {
			_, key := group_of(f, f.listing.entries[f.shown[row]])
			if key in f.folded { folder_set_row(f, row, b.keeping && f.ids[row] in b.base) }
		}
	}
	app_frames(app)
}

// Escape in a band: the selection there was before it.
band_cancel :: proc(app: ^App) {
	b := &app.band
	t := find_tab(app, b.tab)
	if t == nil {
		b.active = false
		return
	}
	_ = ui.item_band_cancel(&b.band, &t.folder.selection, folder_rows(&t.folder))
}
