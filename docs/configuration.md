# Configuration

Classeur reads its preferences from `$XDG_CONFIG_HOME/FromentSoftware/Classeur/prefs` (a line `name<TAB>value` each, after
the first line). The settings (Ctrl+,) show them on a page per subject, searched as you type, each change applied at once.
`--pref name=value` sets one for a single run:

```sh
classeur --pref appearance.mode=light --pref files.show_hidden=true
```

The settings page also exports them to JSON, TOML or INI, or to classeur's own format, which it imports back.

## The common settings

The look (`appearance.*`: the theme, light or dark, the finish, the glow, the text size, the zoom, the density, the
rounding, the rows...), the text and fonts (`appearance.text.*`), the window (`window.system_title`,
`window.toast_position`), the scrolling (`scrolling.*`), the input (`input.*`), the delays and menus (`timing.*`), the
rendering (`rendering.*`), the updates (`update.auto`, `update.channel`, `update.base_url`), the messages
(`general.messages`, `general.language`) and your keys and aliases of the commands (`keys.custom`, `keys.aliases`: set
from the command palette, Ctrl+Enter and Alt+Enter on a command) are the settings that every program of gui_toolkit has.
Its [docs/settings.md](https://github.com/sachahjkl/gui_toolkit/blob/main/docs/settings.md) lists each with its default.
Classeur's defaults: the theme `Graphite`, the text size 14 px, its own title bar (`window.system_title` off), and the
rows with a thin line under each and no stripes (`appearance.rows.rules` on, `appearance.rows.zebra` off).

`appearance.theme` is `Graphite`, a theme of gui_toolkit by its name (Midnight, Nord, Dracula, Gruvbox, Tokyo Night,
Catppuccin, Rosé Pine, Kanagawa, One Dark, Solarized...), or one of your own: Settings > Appearance links to
`$XDG_CONFIG_HOME/FromentSoftware/Classeur/themes.txt`, made with a commented guide at the first click and read again
each time it is saved.

`appearance.text.*` sets the fonts: gui_toolkit loads a family and swaps it in every window at once. Classeur reads
`appearance.text.emoji_font` at the start. `general.menu` and `general.autostart` are the install's (its dialog, the
settings' Installation page, `classeur --install`): their switches show once this copy is the installed one.

## Classeur's own

The details' columns, their widths and the sidebar's order are the program's own memory of what you changed: the
settings do not show them, and the header and the sidebar change them.

| Name | Type | Default | What it does |
|---|---|---|---|
| `appearance.inactive_opacity` | fraction, 0.3 to 1 | 0.8 | Dims the contents of the panels that do not have the keyboard, so that the one that has it stands out. |
| `files.show_extensions` | boolean | true | Shows the extensions of the files' names. |
| `files.show_hidden` | boolean | false | Shows the hidden files (their names start with a dot; on Windows, their attribute). Ctrl+H switches them. |
| `files.folders_first` | boolean | true | Lists the folders before the files, whatever the sort. |
| `files.date_format` | text, `ISO`, `relative` or `day month year` | ISO | How the dates read: `2026-11-09 21:40`; `today 21:40`, `yesterday 21:40`, the weekday for the last week, then `Nov 9, 21:40`; or `Nov 9 2026 21:40`. |
| `files.measure_folders` | boolean | true | Measures the folders shown: what they hold all the way down, in the Folders, Files and Size columns. |
| `view.columns` | text | modified,type,folders,files,size | The columns of the details shown after the name, in their order (`modified`, `type`, `folders`, `files`, `size`). A right click on the header changes them. |
| `view.column_widths` | text | empty | The widths of the details' columns that were resized, in ems (`size=8.0`). Dragging the line before a column's title changes them. |
| `side.order` | text | recents,bookmarks,storage,network,places | The sidebar's sections in their order (`recents`, `bookmarks`, `storage`, `network`, `places`). A drag on a section's heading, or its menu, moves it. |
| `open.single_click` | boolean | false | Opens an item with one click instead of two. |

The session's tabs, panels, folders, bookmarks and recent folders are in
`$XDG_CONFIG_HOME/FromentSoftware/Classeur/session`; the layouts saved by name are
`$XDG_CONFIG_HOME/FromentSoftware/Classeur/layouts`. They are not preferences: deleting one gives its defaults back.

## Examples

Show every file, extensions included, for one run:

```sh
classeur --pref files.show_hidden=true --pref files.show_extensions=true
```

Read the dates whole, and leave the folders among the files:

```sh
classeur --pref files.date_format="day month year" --pref files.folders_first=false
```

A `--pref` value lasts for that run alone. To keep a change, use the settings (Ctrl+,).
