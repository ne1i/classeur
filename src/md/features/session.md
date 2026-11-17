# The session at the start

The session (`session.odin`: the panels and their tabs, the bookmarks, the recent folders) and the layouts
(`layouts.odin`) are two small files of the settings' folder. They come back at the start.

## Decision: read on a worker

The window opens at once with the start's panels: one panel, a tab for each folder of the command line, or one tab at
the home folder. A task of `app.pool` (`start_read_ask`) reads the session file and the layouts file, parses them on its
worker, and posts the result with `ui.post`. The interface's thread applies it (`start_read_done`). It counts in
`app.answers_due`, so the tests' `wait_read` waits for it.

Refused: a read on the interface's thread before the first frame. It was "only two small files", but the settings'
folder can be on a share. A share that does not answer blocks that read, and the window never opens.

## The state machine: `app.start_read`

- `Reading`: the task runs. The zero value, so a new `App` starts in it. Nothing of the session or of the layouts is
  written in this state (see below).
- `Applied`: the answer came and was applied. If the session had panels, they replaced the start's panels; if it had
  none (no file, a file with no tab), the start's panels stay.
- `Dropped`: the answer came after the person changed the panels or the tabs. Its panels are dropped.

When the read has no file to read (headless with no session file given), `start_read_ask` goes to `Applied` at once.

### The rule: the person's first action wins

The session's panels replace the start's panels only if the person has not acted yet. Two signals say that they acted:

- The panels changed. `start_read_ask` keeps the start's panels as text (`panels_text`, the session's own format) in
  `app.start_panels`. At the answer the panels are written as text again: if the text differs, they changed. Any
  change counts: a tab opened, closed, moved, a folder entered, a sort, a zoom, a panel, a second start's folders. The
  comparison is one pass over the tabs, once.
- A key, a text, a mouse button or a finger came to the window while `Reading` (`app_input` sets `app.start_acted`). A
  filter typed, a selection, a rename begun are not in `panels_text`, and replacing the tab would lose them.

If either is true, the session's panels are dropped (`Dropped`).

Refused: apply the session over the person's changes, or merge them. A tab the person just opened, or a folder they
entered, must not vanish under them. Merging tabs gives a set of tabs that nobody chose.

A subtle case: a folder of the command line that is gone goes up to its parent when its read comes (`load_done`). If
that read comes before the session's, the session is dropped too. That is rare, and the window then shows what the
person asked for.

The rest of the answer is merged, whatever the state:

- Bookmarks: the file's first, then those the person added before the answer.
- Recent folders: those visited since the start first, then the file's, to `RECENTS_MAX`. This is the order that the
  old synchronous read gave: the start's reads put their folders in front.
- Layouts: the file's, except a name that the person saved before the answer (theirs is newer). If the person saved
  one, the merged list is written.

### The command line's folders

They keep their priority as before. If the session is applied, its panels open, then the command line's folders open in
the panel with the keyboard (`folders_show`), beside the session's tabs. With no session's panels, the start's panel
already holds them. `app.start_folders` keeps them until the answer.

### No write before the answer

`session_save`, `session_autosave` and `layouts_save` write nothing while `start_read` is `Reading`. Else a save before
the answer (a bookmark, a settled change, the window closed at once) writes the start's state over the file and the
last session is lost. A window closed before the answer writes no session: the file stays as it was. The window's
place is a preference of the toolkit (`window.placement`) and is not concerned.

## Tests

`app_open`'s `start_gate` (tests only) holds the task before it reads, until the test posts the semaphore. This makes a
late answer certain: `test_session_late` acts first, checks that nothing is written, then lets the read go and checks
that the person's tabs stay.
