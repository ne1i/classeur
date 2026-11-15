package classeurtool

// shots: the pictures of the README, the program's own frames with no window of the system (src/app_test.odin,
// test_shots: a home folder of made-up files, two panels, the palette).
//
//   classeurtool shots [--out folder]      (default: docs/screenshots)

import "core:fmt"
import "core:os"
import cli "gt:cli"
import toolbox "gt:toolbox"

SHOTS_OUT   :: "docs/screenshots"
SHOTS_FROM  :: "build/session/test_shots"
SHOTS_NAMES :: [?]string{"main", "panels", "palette", "search", "options", "inspector", "goto", "batch"}

// The tests of the program that measure time, each named in TIMED_TESTS: they run only when asked.
TIMED_TESTS :: "classeur.test_close_during_walk"

run_timed :: proc(args: []string) -> cli.Exit {
	p := project()
	if !toolbox.build_native(p) { return .Failed }
	_ = os.make_directory("build")
	extra := []string{"-out:build/test_timed", "-define:ODIN_TEST_THREADS=1", "-define:CLASSEUR_TIMED=true", "-define:ODIN_TEST_NAMES=" + TIMED_TESTS}
	return toolbox.ended(toolbox.run(toolbox.odin_command(p, "test", "src", extra), {echo = true}))
}

run_shots :: proc(args: []string) -> cli.Exit {
	out := SHOTS_OUT
	if len(args) == 2 && args[0] == "--out" { out = args[1] }
	p := project()
	if !toolbox.build_native(p) { return .Failed }
	_ = os.make_directory("build")
	extra := []string{"-out:build/test_shots", "-define:ODIN_TEST_THREADS=1", "-define:CLASSEUR_SHOTS=true", "-define:ODIN_TEST_NAMES=classeur.test_shots"}
	if !toolbox.run(toolbox.odin_command(p, "test", "src", extra), {echo = true}) { return .Failed }
	_ = os.make_directory_all(out)
	names := SHOTS_NAMES
	for name in names {
		from := fmt.tprintf("%s/%s.png", SHOTS_FROM, name)
		data, err := os.read_entire_file(from, context.temp_allocator)
		if err != nil { return toolbox.done(fmt.tprintf("%s was not made", from)) }
		to := fmt.tprintf("%s/%s.png", out, name)
		if os.write_entire_file(to, data) != nil { return toolbox.done(fmt.tprintf("%s cannot be written", to)) }
		fmt.printfln("wrote %s", to)
	}
	return .Done
}
