# classeur: intent

classeur is a file manager: tabs in panels, a command palette, fast search, an inspector, keyboard first. Its model is
File Pilot. This folder follows <https://srcmd.org>: it records why the code has its shape, the decisions, the refused
alternatives, the subtle points. The map of the code (packages, files, threads, tests) is
[docs/architecture.md](../../docs/architecture.md); building and testing is [docs/development.md](../../docs/development.md).

## Overview

- One process, one window per person (`gt:instance`). The interface is built again at every frame from the program's
  data; the data changes only on the interface's thread.
- `src/fs` is the file system with one interface on every system. The interface (`src/*.odin`) never says which system
  it runs on: `classeurtool check` refuses `ODIN_OS` outside `src/fs` and `src/system_<os>.odin`.
- Workers (`gt:tasks` pools in `App`) do every read and write; a task gets a copy of what it needs and posts its result
  with `ui.post`. Separate pools keep slow work from blocking quick work:
  - `app.pool`: folder reads, places, shares, launches. It grows while a read of a share hangs.
  - `app.edit_pool`: one thread, the interface's own changes to files, in the order asked.
  - `app.thumb_pool`: two threads, the newest asked first, a card scrolled past not read.
  - the measures' pool: folders measured all the way down.
- The jobs (copy, move, trash, delete) run one at a time on a thread of their own; a name taken asks the interface and
  the job waits on a semaphore.
- Files written while the window runs (the session, the layouts) are each a `store.Writer`; the preferences are a
  `config.User_Writer`.

## State machines

- A tab's read: asked (with a `serial`), then done; an answer with an old serial is dropped.
- A job: counting, copying, asking (name taken), done or cancelled.
- Who has the keyboard (`app.keys_at`): see [features/keyboard.md](features/keyboard.md).
- A paste: asked of the clipboard, then started when the files come (a `Clipboard_Data` event).
- The undo stack: steps of (before, after) paths, undone and redone through free names.

## Subtleties

- The interface's thread never waits: not a `stat`, not a mount table, not a clipboard of files. A share that hangs
  must never freeze the window. Only the reads of the start (the preferences, the session, the layouts) run there, before
  the first frame.
- A frame does no work in proportion to the number of entries: orders, counts and sizes are made when the data changes
  and kept.
- The Recycle Bin of Windows is no folder: `fs.list` reads every drive's `$I` records into a listing whose entries
  carry their real paths (`Listing.trashed`).
- A rename never replaces (`fs.rename`).
- The person reads the name `APP_TITLE` ("Classeur"); `APP_NAME` ("classeur") stays the technical one. The settings,
  the state and the caches are in the vendor's folder (`APP_FOLDER`, `FromentSoftware/Classeur`). `app_run` moves the
  folders of the old name there once (`platform.user_dirs_move`). The single instance's name keeps `APP_NAME`: an old and
  a new copy still find each other.
- The tests open the real program headless; they wait for the answers with `wait_read` (`app.answers_due`), never for
  a delay.

## File Index

- [layers.md](layers.md): how the program grew layer by layer, and the decisions of each layer (jobs, the clipboard of
  files, the trash, undo, batch rename, thumbnails); the known gaps
- [features/keyboard.md](features/keyboard.md): the order in which a build reads the keys, the person's keys and
  aliases (the toolkit's keymap, classeur's ids), who has the keyboard, why F6 stays classeur's
- [features/palette.md](features/palette.md): the command palette's sources (commands, moves, settings, `@` tabs, `/`
  folders), what reads on the workers, what each choice does, the buttons go to reaches, the commands with arguments
- [data/folder.md](data/folder.md): a folder as a panel shows it: the selection as flags, the worker that prepares the
  order, the serial of a read, edits in order
