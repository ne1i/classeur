# GoTo and the path field: the deep search

GoTo (Ctrl+G) and the path field of a panel (Ctrl+L, or a click on the empty part of the crumbs) answer one question:
"where do I want to go?". Both give the same rows, from `goto_rows`. GoTo is a dialog; the path field shows its rows in a
list that drops down under it, in the panel's toolbar. A click on the toolbar never opens a dialog over the panel.

## What a text finds

- **An absolute path** (`/`, `~`, a drive): the entries of the folder it names so far, found by the letters after its last
  separator. Folders and files. Tab completes the path to the row chosen.
- **Anything else**: the recent folders, the bookmarks and the places whose path has the letters, then every file and
  folder **below the current folder, at any depth**, best first.
  - Without a separator, the letters are matched against each entry's own name ("logo" finds `brand/logo.svg`).
  - With a separator, they are matched against the entry's path from the current folder, so
    `packages/web/public/brand/logo.svg` finds that file. A relative path that exists is the first row, even before
    the walk reaches it.
  - A shallower entry ranks a little higher than a deeper one with the same letters.
  - Entries under a hidden folder (its name starts with a dot) are left out unless hidden files are shown or the text
    starts with a dot.

Enter goes to the row chosen; a file's row opens its folder with the file at the cursor (`tab_go`).

## Why an index, and where it lives

`deep_find.odin` keeps a `Deep_Index`: every entry under one folder, named by its path from that folder. A walk
(`fs.walk`, its threads) fills it on a worker of `app.pool`, batch by batch, so rows come while the walk runs. Each text
typed asks a match of a worker: it scores the index's entries and posts the best `DEEP_ROWS`. The interface's thread
never walks, never scores, and never goes through the entries: a frame reads the rows of the last answer.

- Only one match is in flight. A text typed meanwhile is asked when that answer comes; the answer of an older question
  is dropped (`serial`).
- While the walk runs, a new batch moves `version`; the next frame asks the match again for the same text.
- The index is read again at each opening of GoTo or of the path field: a file made since is found. While the dialog
  or the field stays open on one folder, the index is kept.
- The index is shared by the walk, the matches and the interface, each holding a reference (`refs`). The last one
  frees it. Letting it go sets `stop`: the walk ends at its next folder.
- The walk stops at `DEEP_MAX_ENTRIES`: a search from `/` must not take the machine's memory. The rows say how many
  entries were read.

Refused: listing the current folder's entries in each frame (GoTo did it: a pass in proportion to the folder at every
frame), and a walk per letter typed (the same tree read again at each key).
