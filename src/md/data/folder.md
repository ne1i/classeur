# A folder as a panel shows it

`Folder` (`src/folder.odin`) holds a listing, its order, the rows shown (filter, hidden files) and the selection with
its cursor. It has no interface.

## Decisions

- **One listing, one arena.** `fs.list` gives one array of `Entry` with the names in one arena.
- **The selection is the toolkit's `Item_Selection`**, the one every list of the programs has (gui_toolkit's
  `src/md/features/selection.md`): click, Ctrl, Shift and Ctrl+Shift, the keys, the anchor and its base. Its `sel` is
  the cursor. The folder keeps no rules of its own: `folder_pick` passes a press and its modifiers to the model, the
  list's keys pass the row a key goes to (`item_selection_move`), the grid's by cards, the columns view's by lines.
  An own model with a flag per entry was refused: it was the toolkit's rules written a second time, a little different
  (Shift added to the selection).
- **The rows' ids are the hashes of their names.** The selection holds ids, so it survives a sort, a filter that keeps
  the rows and a new listing of the same folder with no pass to translate it. A row the filter hides leaves it
  (`item_selection_keep` in `folder_refilter`): what is selected is what the person sees.
- **The bytes of the selection follow its version.** `folder_selection_size` counts them again once after a change (a
  pass over the rows, in the frame after the gesture). The rectangle tells each row it changes (`Item_Band.changed`,
  `src/band.odin`): the bytes follow each row, so a rectangle drawn over 100 000 rows costs the rows it touches at each
  frame, not a count.
- **A folded group's title row cannot be selected** (`selectable`, made with the rows, given in `folder_rows`). Its
  files are hidden; selecting its first file would let an action act on a file the person does not see.
- **The rectangle feeds the same model.** Its base is the set of ids at the press; it sets the rows it touches and
  moves the cursor. When it ends, the anchor is dropped: a Shift range after it starts from the cursor, over what the
  rectangle selected.
- **The worker prepares, the interface swaps.** The worker sorts and filters the listing with a copy of the tab's
  settings (`folder_view_copy`, `folder_prepare`). `load_done` swaps the prepared arrays in (`folder_take`) and only puts
  the cursor back by name; the selection is ids and stays. The interface's thread never sorts 100 000 entries.
- **A serial per read.** `tab_load` gives a task to the workers; `load_done` gives the listing to the tab only if it is
  the read the tab waits for (`serial`). A read that is no longer wanted (the tab went elsewhere) still runs; its result
  is dropped.
- **Edits in order.** The changes the interface makes itself (a rename, a new folder or file, a batch rename, their undo
  and redo) go to one worker of their own (`app.edit_pool`, one thread), so they are done in the order asked. The
  interface keeps what it shows until the answer: the rename's field stays open.
- **An archive.** Whether the folder is in an archive (`Tab.in_archive`) is read on a worker: what writes is refused at
  once.
