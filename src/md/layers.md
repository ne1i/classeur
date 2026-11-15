# The layers

classeur is built in layers: each layer adds to a program that works. Its model is File Pilot (filepilot.tech): copy its
behaviour where it is good, with no shame. Two constraints hold for every layer:

- A folder of 100 000 files must read and scroll without a wait.
- The program is the same on Linux and Windows.

This file keeps, per layer, the decisions that the code does not explain. The planned work is in
[ROADMAP.md](../../ROADMAP.md); the map of the code is [docs/architecture.md](../../docs/architecture.md).

## Layer 1: browse

- A folder is read on the workers (`fs.list`: getdents64 + statx on Linux, FindFirstFileExW on Windows); the answer
  comes through `ui.post`; only the last read asked counts.
- The details view is a virtual list: only the rows in view are built.
- The natural sort: digits by value, case and Latin accents ignored.
- The selection survives a sort, a filter and a refresh: it is a flag per entry, and a new listing gets it back by name.
- Backspace and Alt+Up put the cursor on the folder we came from. A typed path that names a file opens its folder with the
  file at the cursor.
- The crumbs start at Home under the home folder; the first crumbs go when the room is short.
- The tests drive the whole program with no window of the system (`src/app_test.odin`); the README's pictures come from a
  test.

## Layer 2: change files

- **Jobs.** Copy, move, trash, delete run one at a time on a thread of their own (`src/jobs.odin`); progress is in
  atomics. A copy counts first, then copies. A cancelled copy leaves nothing. A move is a rename on its volume, else a
  copy then the source removed. A folder onto a folder merges.
- **A name taken** asks (`src/dialogs.odin`): replace, skip, keep both ("name 2.ext"), the same for the next ones; the job
  waits on a semaphore for the answer. Pasted into the folder it comes from, a copy keeps both without asking.
- **The clipboard of files.** A cut is a move for every file manager: gui_toolkit's `files_cut` writes
  `x-special/gnome-copied-files`, `application/x-kde-cutselection` and Windows' `Preferred DropEffect`. A paste asks
  with `platform.clipboard_request` and starts its job when the files come: a program that holds the clipboard and does
  not answer never freezes the window.
- **The trash.** Linux: the freedesktop.org specification (home trash on its volume, else `<top>/.Trash-<uid>`, a
  `.trashinfo` taken with `O_EXCL`). Windows: the Recycle Bin. Shift+Delete deletes for good after a confirmation.
  - Undo needs the item's place in the Recycle Bin, its `$R` file. On Windows, `IFileOperation` gives it to the sink of
    the delete (`PostDeleteItem`, its new item). Refused: the search of the `$I` records written since the trash began,
    by path and date. A clock or a timestamp off by a moment, or a record not yet seen, lost it now and then. The
    trash then left no undo step, and each Ctrl+Z after it undid a step older than the one the person meant.
  - An item that the shell deletes for good (a drive without a Recycle Bin) has no new item: no undo step.
- **Watching.** Changes close together come as one; a folder read again keeps its cursor and its selection.
- **The look** is File Pilot's, faithfully. No status bar: messages are toasts. The zoom goes from the details (0 %) to
  names alone (10 %), names in columns (20 %), then cards ever larger (30 % to 100 %).
- **Thumbnails** are decoded and shrunk to 256 px on a pool of their own; the textures of the 400 last used are kept.
- **Folder measures** run on a pool of their own (2 threads), kept by path and date; a navigation drops the measures not
  started.

## Layers 3 to 6

- **Undo and redo** (`src/undo.odin`): a stack of steps, each a list of (before, after) paths. The jobs record what they
  did (`Job.done`). Renames go through free names in two steps, all or nothing. What
  an undo removes goes to the trash, never deleted for good.
- **GoTo** (`src/goto.odin`): the folder a path names is read on a worker; its folders are found by the letters after the
  last separator.
- **Batch rename** (`src/batch.odin`): the problems come from the names read at the opening, never from the disk while
  typing.
- **Drag and drop** (`src/dnd.odin`): the places that take a drop are noted each frame. Tabs dragged and torn off at the
  window's edge (`src/tab_drag.odin`); the rectangle selection (`src/band.odin`).
- **One window per person** (`gt:instance` `serve_start`), the session (`src/session.odin`).
- Back and Forward come back to the row and the scroll left (`Visit`, `src/tab.odin`). A refused rename keeps its name.
- The letters typed go to the panel's filter (`no_typeahead`), not to a jump in the list.

## The system's thumbnails

- The inspector shows a PDF's first page and a frame of a video: the system's large thumbnail, said so under it
  (gui_toolkit's `desktop.thumbnail`).
- A large picture's thumbnail (over 2 MB) is read from the system's cache first and kept there once decoded.

## Known gaps

- The sessions of papier and classeur both have a shots command; papier's runs a headless sway, classeur's runs
  headless in a test. If papier moves to the headless test, nothing is left to share.
- Windows: the CI runs the tests and checks the icon and `classeur.com` there. Drags between two real windows are tested
  by hand only.
