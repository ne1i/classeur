# The command palette

classeur's palette is the toolkit's (`ui.Command_Palette`; its intent is gui_toolkit's `src/md/features/palette.md`):
the same look, keys and prefixes as in the other programs. classeur gives it its data as **sources**
(`src/palette.odin`, `src/palette_sources.odin`); the palette asks them, ranks their items on a chore and returns the
choice as a source and an id.

## The sources

| Prefix | Source | Items | Choosing |
|---|---|---|---|
| `>`, plain | the commands (`ui.palette_commands`) | `COMMANDS` by group, the person's keys, the aliases as tags | runs it; Ctrl+Enter records a key of one's own, Alt+Enter makes the letters typed its alias (the source's alternates) |
| `>`, plain | the views' moves (the toolkit's) | float, dock, re-attach, close each open view | the toolkit runs it |
| `:`, plain | the settings (`prefs_page.palette_settings_add`) | each setting the pages show | a switch flips, the palette stays; another opens the settings on it |
| `@`, plain | the tabs | every tab, under its panel's name; the shown one marked | its panel gets the keyboard and shows it |
| `/`, plain | the folders | the folders of the path typed, and the recent folders, bookmarks and places the letters find | goes there in the tab; Ctrl+Enter in a new tab; Tab completes the path |

## Decisions

- **The tabs source replaces "Tab 1" to "Last tab" in the palette.** They showed once "tab" was typed: a rule of
  classeur's own. They stay commands (Alt+1 to Alt+9), out of the palette's table.
- **A command that cannot act now is listed, greyed and last** (the toolkit's rule), not hidden as before. The table
  of the commands source is made again when the keymap or the language changes; what can act is a bit per gated
  command, read at each build (three commands), and a change of it bumps the source's version: the palette compares
  versions, never `disabled`.
- **The folders are read on the workers.** A question for a path lists its folder on `app.pool`; the job also gets a
  copy of the recent folders, the bookmarks and the places (lists of a few dozen) and finds them by the letters there.
  The answer is built in the job's own arena and given whole (`ui.palette_answer`) by the job itself: an end is safe
  from any thread. The interface's thread never lists a folder nor matches a name.
- **One listing per folder while typing.** The folders source is asked at each letter. The last folder listed is kept
  (`Folders_Cache`: its path, its modification time, its folders' names, under a mutex): a job that finds the same path
  and the same time takes the names from there, after one `stat`. A folder changed since (an entry made or removed
  changes its time) is listed again.
- **What `/` means.** The prefix is the path's first separator on Linux and macOS: `/home/x` lists `/home`'s folders
  whose names have `x`. `~` is the home folder. On Windows a drive or a share after `/` (`/C:\Users`) is a path. Words
  after `/` find the recent folders, the bookmarks and the places.
- **Ctrl+K and Ctrl+Shift+P are the toolkit's** (`ui.palette_keys`), and so is its command (`ui.palette_command`): the
  sheet lists it, classeur's table has no line for it, the "…" menu builds its line from it. The keys wait while the
  recorder is open, as the window's commands do: it records any chord.
- **The settings source is added once.** Its page options are read when it needs them (`options_page`, a procedure):
  the updater and the themes shown as they are then.
- **Personal keys and aliases stay classeur's** until the toolkit has them for every program: the alternates of the
  commands source, and its `first` (an alias typed whole).

## Refused

- **Decoding a chosen index by ranges** (commands, then settings, then moves): it broke when the table was made again
  between the choice and its reading. A choice is a source and an id.
- **GoTo's suggestions as the folders source** (`goto_rows`): it matches on the interface's thread, at each key.

## Subtle points

- The usage memory's keys are `<source>:<id>` (`command:tab_new`): the file of before (`palette_choices`) is not read;
  the memory starts again in `palette_choices.txt`.
- The tabs' ids last one run: the tabs source does not remember its choices.
- The tabs source follows the panels with a small signature made while the palette is open (`poll`): the ids, the
  paths, which tab is shown, which panel has the keyboard. A few dozen tabs: no pass over a folder's entries.
- Alt+Enter makes the choice's query (`Palette_Choice.query`, its prefix left out) an alias: not the field read after
  the palette closed.
