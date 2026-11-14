# The keyboard

Every action is a command of `src/commands.odin`: the keyboard, the palette and the menus read that one table. No key is
read elsewhere unless it moves in a list or a field. The keys go through a fixed order in each build; who has the
keyboard is a small state machine (`app.keys_at`: the sidebar, a panel's list, the inspector, a view).

## The order of a build

1. `view_build` reads the keys of the commands first (`commands_keys`). While a text field has the keyboard, only the
   commands marked `in_text` run. The fields built in the last frame are noted in `app.text_keys_before`: this frame's
   fields are not built yet when the commands read the keys.
2. Then the keys of the selection (`list_keys` in `view.odin`: Shift ranges, Ctrl+Space, Escape, Menu).
3. Then the virtual list of the focused panel takes the moves (Up, Down, Page Up, Page Down, Home, End). It takes no
   letter (`no_typeahead`): the letters typed go to the panel's filter (`type_to_field`). A move of the list selects the
   cursor's row alone (`folder_pick`). The list has the keyboard from the start (`app_open`).

## Who has the keyboard

- A press in a panel gives it the keyboard. Unless the press is on a text field, the list gets the focus back at the
  next build (`Tab.focus_due`).
- F6 and Ctrl+Shift+F6 move the keyboard round its stops: the sidebar, each panel's list, the inspector. While the
  sidebar or the inspector has it, the list's keys do not run and only the `in_text` commands do; Escape gives it back to
  the list.
- These keys are read inside the views' frame, after the views docked or floating: a view with the focus reads its keys
  first. The toolkit's F6 comes last and only when nothing took it, so F6 and Shift+F6 stay classeur's.
- A view shown as a dialog holds the keys (`ui.views_hold_keys`: `app.no_dialog` false). A view that floats, is docked
  or is in a window keeps the focus it is given: while the focus is in it (`focus_in_view`, from `ui.views_focus`), only
  the `in_text` commands run.
