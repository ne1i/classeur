package classeur

// The keys that type text (gui_toolkit's src/md/features/commands.md): a command marked `in_text` runs while a field has
// the keyboard, so none of its keys may type text; the others that do are listed on purpose.

import "core:fmt"
import "core:slice"
import "core:testing"
import "gt:testkit/unwatched"
import "gt:ui"

@(test)
test_command_keys_typing_text :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		typing := make([dynamic]string, context.temp_allocator)
		for c in COMMANDS {
			for k in c.keys {
				if !ui.command_key_types_text(k) { continue }
				testing.expectf(t, !c.in_text, "%s: %v types text and runs while a field has the keyboard", c.id, k)
				append(&typing, fmt.tprintf("%s: %v", c.id, k.key))
			}
		}
		testing.expectf(t, slice.equal(typing[:], []string{"up: Backspace", "inspector: Space"}), "keys that type text: %v", typing[:])
	})
}

// Every command has an id the keymap can store (keys.custom, keys.aliases) and the palette's memory remembers: no
// empty, malformed or duplicate one.
@(test)
test_command_ids :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		table: [len(COMMANDS)]ui.Command
		commands_make(table[:])
		got := ui.command_ids_check(table[:])
		testing.expectf(t, len(got) == 0, "wrong ids: %v", got)
	})
}

// The window's commands (window_keys): the keys, the settings and quit, each also in_text (the palette's is the
// toolkit's: ui.palette_command).
@(test)
test_window_commands_marked :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		for id in ([]string{"options", "shortcuts", "app_quit"}) {
			c := command_find(id)
			testing.expectf(t, c != nil && c.scope == .Window && c.in_text, "%s is the window's", id)
		}
		for c in COMMANDS {
			if c.scope != .Window { continue }
			for k in c.keys { testing.expectf(t, !ui.command_key_types_text(k), "%s: %v types text", c.id, k) }
		}
	})
}
