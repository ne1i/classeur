#+build !windows
#+build !linux
package fs

// Another system (macOS first): the root only. No trash yet (trash_other.odin).

import "core:strings"
import "gt:i18n"

System_Place :: struct { name, path: string }

system_places :: proc(allocator := context.allocator) -> []System_Place {
	out := make([dynamic]System_Place, allocator)
	append(&out, System_Place{i18n.tr("Computer"), strings.clone("/", allocator)})
	return out[:]
}
