# The keyboard

Every action is a command of `src/commands.odin`: the keyboard, the palette and the menus read that one table. No key is
read elsewhere unless it moves in a list or a field. The keys go through a fixed order in each build; who has the
keyboard is a small state machine (`app.keys_at`: the sidebar, a panel's list, the inspector, a view).

## The order of a build

0. `view_build` reads the palette's keys first, Ctrl+K and Ctrl+Shift+P (the toolkit's `ui.palette_keys`, in
   `palette_keys_read`: the command is the toolkit's, `ui.palette_command`, with no line in `COMMANDS`), then the keys of the
   window's commands (`window_keys`: the keys, the settings, quit; `scope = .Window`). They work in every page and
   whatever has the keyboard: a field, the sidebar, a view, and over a view shown as a dialog (the settings are one). The
   toolkit's `ui.command_pressed` takes their chords from wherever the focus is. One exception: while the toolkit's
   recorder of a command's keys is open, they wait. It records any chord, Ctrl+K too, and claims them all
   (`ui.keys_claim`).
1. Then the keys of the page's commands (`commands_keys`). While a text field has the keyboard, only the
   commands marked `in_text` run. The fields built in the last frame are noted in `app.text_keys_before`: this frame's
   fields are not built yet when the commands read the keys.
2. Then the keys of the selection (`list_keys` in `view.odin`): the moves with Shift (a range), Ctrl+Shift (a range
   added) and Ctrl (the cursor alone), Ctrl+Space, Escape (several rows: the cursor's alone, `item_selection_escape`), Menu. Each key gives the row it goes
   to, and the toolkit's `item_selection_move` gives the modifiers their meaning. Ctrl+Page Up and Ctrl+Page Down stay
   the tabs'. The grid and the columns view take their plain moves here too: they move by cards and by lines.
3. Then the virtual list of the focused panel takes the plain moves (Up, Down, Page Up, Page Down, Home, End). It takes
   no letter (`no_typeahead`): the letters typed go to the panel's filter (`type_to_field`). A move of the list selects
   the cursor's row alone (`folder_pick`). The list has the keyboard from the start (`app_open`).

## The person's keys and aliases

The person's keys (Ctrl+Enter on a command of the palette) and aliases (Alt+Enter) are the toolkit's `ui.Keymap`, the
same in every program of the family: its intent is gui_toolkit's
[src/md/features/keymap.md](../../../ext/gui_toolkit/src/md/features/keymap.md). Classeur had them first; the toolkit
took its design, and classeur keeps none of it.

- `COMMANDS` stays classeur's table: `run`, `enabled` and `in_text` are its own. `commands_make` derives `app.commands`
  from it once, a `ui.Command` per line at the same index, and every reader of keys reads that one: `window_keys`,
  `commands_keys`, the palette, the sheet, the menus and the tooltips.
- **A command's id never changes.** It is the key of `keys.custom`, `keys.aliases` and the palette's memory. The ids
  are the ones classeur stored before the toolkit had a keymap: the values of a person who set keys still apply.
- The two settings are the toolkit's standard ones (`Standard_Set.Keys`, under the same names). `standard_watch` reads
  them into `app.keymap` and writes them back.
- `ui.keymap_known` runs before the preferences are read and before the first `command_pressed`. Else a person's key on
  an id not yet known takes no chord, and the command's own key acts once.

## Who has the keyboard

- A press in a panel gives it the keyboard. Unless the press is on a text field, the list gets the focus back at the
  next build (`Tab.focus_due`).
- F6 and Ctrl+Shift+F6 move the keyboard round its stops: the sidebar, each panel's list, the inspector. While the
  sidebar or the inspector has it, the list's keys do not run and only the `in_text` commands do; Escape gives it back to
  the list.
- These keys are read inside the views' frame, after the views docked or floating: a view with the focus reads its keys
  first. The toolkit's F6 comes last and only when nothing took it, so F6 and Shift+F6 stay classeur's.
- A view shown as a dialog holds the keys of the page's commands (`ui.views_hold_keys`: `app.no_dialog` false), not the
  window's. A view that floats, is docked
  or is in a window keeps the focus it is given: while the focus is in it (`focus_in_view`, from `ui.views_focus`), only
  the `in_text` commands run.
