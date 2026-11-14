# A folder as a panel shows it

`Folder` (`src/folder.odin`) holds a listing, its order, the rows shown (filter, hidden files), the selection, the cursor
and the anchor of Shift ranges. It has no interface.

## Decisions

- **One listing, one arena.** `fs.list` gives one array of `Entry` with the names in one arena.
- **The selection is a flag per entry**, not a list of rows: it survives a sort or a filter with no pass to translate it.
- **The worker prepares, the interface swaps.** The worker sorts and filters the listing with a copy of the tab's
  settings (`folder_view_copy`, `folder_prepare`). `load_done` swaps the prepared arrays in (`folder_take`) and only puts
  the selection and the cursor back by name. The interface's thread never sorts 100 000 entries.
- **A serial per read.** `tab_load` gives a task to the workers; `load_done` gives the listing to the tab only if it is
  the read the tab waits for (`serial`). A read that is no longer wanted (the tab went elsewhere) still runs; its result
  is dropped.
- **Edits in order.** The changes the interface makes itself (a rename, a new folder or file, a batch rename, their undo
  and redo) go to one worker of their own (`app.edit_pool`, one thread), so they are done in the order asked. The
  interface keeps what it shows until the answer: the rename's field stays open.
- **An archive.** Whether the folder is in an archive (`Tab.in_archive`) is read on a worker: what writes is refused at
  once.
