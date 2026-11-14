# classeur

A file manager for Linux and Windows, in Odin, on the `ext/gui_toolkit` submodule (collection `gt`). Its model is File
Pilot (filepilot.tech): tabs in panels, a command palette, fast search, an inspector, keyboard first.

Read first: [README.md](README.md), [src/md/README.md](src/md/README.md) (the intent),
[docs/architecture.md](docs/architecture.md), [ROADMAP.md](ROADMAP.md), [docs/development.md](docs/development.md).

## Build and test

Every step is a command of `tools/classeurtool` (`help` lists them):

    odin run tools/classeurtool -collection:gt=ext/gui_toolkit/src -out:build/classeurtool -keep-executable -- <command>

- `build [release]` builds `build/classeur` (`build.sh` / `build.bat` are shortcuts).
- `test`: the tests of `src` (the whole program with no window of the system), `src/fs` and the tool.
- `check`: `odin check -vet` (and `src/fs` for the other system), the tests, a release build.
- `shots` makes the README's pictures from `test_shots`, `logo` the logo.
- `timed`: the tests that measure time, opt-in (`when !TIMED { return }`); `check` does not run them.
- Linux: `nix develop` first (`flake.nix`).

## Rules

- Every action is a command of `src/commands.odin` (title, icon, keys) with its procedure in `src/actions.odin`: the
  keyboard, the palette and the menus read that table. No key is read elsewhere unless it moves in a list or a field.
- The interface's thread never waits. No disk, network or system call runs there, in a build, a draw, an input or an
  action: not a `stat`, not a small read, not a rename, not a mount table, not a clipboard of files. Reading a folder,
  measuring, copying, renaming, making a folder, the volumes, the shares: all are tasks of the workers (`gt:tasks` pools in `App`)
  whose results come back with `ui.post`. A share that hangs must never freeze the window.
- A frame does no work in proportion to the number of entries: no sort, no full filter, no pass over every row or every
  entry, no allocation per entry. Counts, sizes and orders are worked out when the data changes (on a worker for a
  listing) and kept; a frame reads what it shows.
- The tests never touch the person's files or desktop: they make their folders with `testkit.temp_folder`, and
  `open_system` starts nothing when the program is headless.
- What more than one program needs goes in gui_toolkit, generic, with its docs, test and changelog fragment; classeur then
  points to the toolkit's new commit.
- A change a person sees adds one fragment to `changelog.d/` (`classeurtool changelog new ...`), in the same commit;
  `CHANGELOG.md` is never edited by hand: `ship` assembles the fragments.
- Automation is a command of `tools/classeurtool`, never a shell, batch, PowerShell, Python or Node script.
- Comments and commit messages are in English. Comments say why.
- Commits: author and committer `sachahjkl <sacha@sacha.house>`, no attribution trailer, no session link.

## Roadmap

- `ROADMAP.md`, beside `CHANGELOG.md`, holds classeur's planned work: `# Roadmap`, then `## Now`, `## Next` and
  `## Later`, each a list. Each entry starts with a bold summary, then one or two sentences on what it gives the user. No
  dates, no front matter.
- When a work is done, remove its entry in the same commit as its changelog fragment.
- Work that touches several programs goes in the roadmap of gui_toolkit.
- `classeurtool check` checks its format with the changelog's.

## Intent

This project follows <https://srcmd.org>, with the Markdown in `src/md`. Read `src/md/README.md` first.

- Change the intent first, then derive the code and the tests. A change of design changes its intent file in the same
  commit.
- Keep there what the code does not show: the purpose, the decisions, the refused alternatives, the subtle points.
- `src/md/README.md` lists every other file of the folder in its `## File Index`.
- The user's documentation and the developer's how-to stay in `docs/`; `src/md` links to them.

## Pitfalls met

- `if !ui.row(...) { return }` closes the row at once (the scope of a deferred procedure is the `if`): build children
  inside `if ui.row(...) { ... }`. `classeurtool check` refuses it.
- A test that calls the program's procedures sets `context.allocator = runtime.heap_allocator()` first: what the program
  keeps must come from its own allocator, not from the test's tracking one.
