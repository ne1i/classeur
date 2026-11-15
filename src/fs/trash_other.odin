#+build !windows
#+build !linux
package fs

// Another system (macOS first): no trash yet. Its trash (~/.Trash, with the Finder's records of where an item was)
// needs the system's own interface: a move there without them could not be put back by the Finder. Until then a
// trash fails, and nothing is deleted in its place.

// Moves `path` to the trash: never done here (.Other), so that the file stays where it is.
trash_native :: proc(path: string, allocator := context.allocator) -> (in_trash: string, e: Error) { return "", .Other }

untrash :: proc(in_trash: string, allocator := context.allocator, to := "") -> (original: string, e: Error) { return "", .Other }

trash_origin :: proc(in_trash: string, allocator := context.temp_allocator) -> (original: string, ok: bool) { return }

// No trash: no item of it has a record.
trash_record :: proc(in_trash: string, allocator := context.temp_allocator) -> string { return "" }

// No trash: every folder is read as a folder.
list_trash :: proc(l: ^Listing, path: string) -> (e: Error, done: bool) { return .None, false }

trash_title :: proc(path: string) -> string { return "" }
