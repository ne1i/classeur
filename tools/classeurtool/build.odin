package classeurtool

// build, test, check: the toolkit's (toolbox.build_commands), with classeur's own checks.

import "core:fmt"
import "core:os"
import "core:strings"
import changelog "gt:changelog"
import toolbox "gt:toolbox"

// (src: one thread, each test said as it starts: a test that hangs is the last one said; the CI's log shows it)
@(rodata) TESTS := [?]toolbox.Test_Package{{path = "src", one_thread = true}, {path = "src/fs"}, {path = "tools/classeurtool"}}
@(rodata) CHECKS := [?]toolbox.Build_Check{check_systems, check_fs_other}

build_options :: proc() -> toolbox.Build_Options {
	p := project()
	return {project = p, changelog_command = changelog.command(p), tests = TESTS[:], catalogues = I18N, checks = CHECKS[:]}
}

// Windows: the file system's code of the other system (the program is written for both; Linux checks Windows itself).
check_fs_other :: proc(p: toolbox.Project) -> bool {
	when ODIN_OS == .Windows {
		return toolbox.run({"odin", "check", "src/fs", fmt.tprintf("-collection:gt=%s/src", toolbox.toolkit_dir(p)), "-vet", "-no-entry-point", "-target:linux_amd64"}, {echo = true})
	} else {
		return true
	}
}

// The system and the interface apart: the interface (src/*.odin) asks src/fs and the toolkit (platform, desktop) what
// differs between the systems, and says nothing of them itself. A difference of the program's own is a constant in a
// file of the system's name (system_windows.odin, system_other.odin), never a `when ODIN_OS` in the interface.
check_systems :: proc(_: toolbox.Project) -> bool {
	files, ok_files := source_files("src")
	if !ok_files { return false }
	ok := true
	for f in files {
		if !strings.has_suffix(f.name, ".odin") || strings.has_suffix(f.name, "_test.odin") || strings.has_prefix(f.name, "system_") { continue }
		data, rerr := os.read_entire_file(f.fullpath, context.temp_allocator)
		if rerr != nil { continue }
		text := string(data)
		n := 0
		for line in strings.split_lines_iterator(&text) {
			n += 1
			if strings.contains(line, "ODIN_OS") {
				fmt.eprintfln("%s:%d: the interface knows the system: ask src/fs or the toolkit, or put a constant in a system_<os>.odin", f.fullpath, n)
				ok = false
			}
		}
	}
	return ok
}

// The program's sources: src/*.odin and those of its packages below (src/update...), src/fs aside (the system's own,
// where ODIN_OS belongs; it builds no interface).
@(private = "file")
source_files :: proc(dir: string) -> (files: [dynamic]os.File_Info, ok: bool) {
	files.allocator = context.temp_allocator
	list, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil { return files, false }
	for f in list {
		if f.type == .Directory {
			if f.name == "fs" { continue }
			sub, sub_ok := source_files(f.fullpath)
			if !sub_ok { return files, false }
			append(&files, ..sub[:])
			continue
		}
		append(&files, f)
	}
	return files, true
}
