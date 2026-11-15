#+build !windows
#+build !linux
package fs

// Another system (macOS first): the root only. Its mounted volumes (/Volumes) are not listed yet.

import "core:strings"
import "gt:i18n"

volumes :: proc(allocator := context.allocator) -> []Volume {
	out := make([dynamic]Volume, allocator)
	append(&out, Volume{path = strings.clone("/", allocator), label = strings.clone(i18n.tr("File system"), allocator)})
	return out[:]
}
