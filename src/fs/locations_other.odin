#+build !windows
#+build !linux
package fs

// Another system (macOS first): paths and file URIs only. No trash (trash_other.odin) and no share is reached yet:
// those schemes say .Unsupported, as sftp:// does on Windows.

import "core:strings"
import "gt:i18n"

location_resolve :: proc(text: string, allocator := context.allocator) -> (r: Location, e: Location_Error) {
	t := strings.trim_space(text)
	if !is_uri(t) {
		if t == "" { return {}, .Not_A_Location }
		return {path = strings.clone(t, allocator), kind = .Path}, .None
	}
	u, _ := uri_parse(t)
	switch {
	case u.scheme == "file":
		return {path = strings.clone(u.path, allocator), kind = .Path}, .None
	case u.scheme == "trash":
		return {kind = .Trash}, .Unsupported
	case is_network_scheme(u.scheme):
		return {kind = .Network, uri = strings.clone(t, allocator)}, .Unsupported
	}
	return {}, .Not_A_Location
}

// No trash: no folder holds its files.
trash_files_dir :: proc(allocator := context.temp_allocator) -> string { return "" }

share_mount :: proc(uri: string, allocator := context.temp_allocator) -> (ok: bool, why: string) {
	return false, strings.clone(i18n.tr("shares are not supported on this system yet"), allocator)
}

location_display :: proc(path: string, allocator := context.allocator) -> string { return strings.clone(path, allocator) }

share_root :: proc(path: string, allocator := context.allocator) -> (root, uri: string, ok: bool) { return }

network_shares :: proc(allocator := context.allocator) -> []Share { return make([]Share, 0, allocator) }
