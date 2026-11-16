package classeur

// The deep search of GoTo and the path field (src/md/features/goto.md): every entry below one folder, walked on a
// worker into an index, matched on a worker; the interface reads the best rows of the last answer.

import "base:runtime"
import "core:slice"
import "core:strings"
import "core:sync"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

// The rows an answer keeps, best first.
DEEP_ROWS :: 60
// The walk stops past this many entries (a search from / must not take the machine's memory).
DEEP_MAX_ENTRIES :: 400_000
// What each level below the folder costs a row's score: a shallow entry before a deep one with the same letters.
DEEP_DEPTH_COST :: 3
// What a name equal to the letters typed earns.
DEEP_EXACT_BONUS :: 1000

// Every entry below `root`, named by its path from it. Shared by the walk, the matches and the interface: each holds a
// reference, the last frees it. In the heap: its owners are several threads.
Deep_Index :: struct {
	root:    string,
	app:     ^App,
	lock:    sync.Mutex,     // over `list`
	list:    fs.Listing,     // what the walk found so far (names in its arena)
	count:   int,            // atomic: len(list.entries), for the interface
	version: int,            // atomic: moves with each batch
	done:    bool,           // atomic: the walk ended
	stop:    bool,           // atomic: the interface let go; the walk ends at its next folder
	refs:    int,            // atomic
}

// A row of an answer: the path from the index's root, and the letters matched in it.
Deep_Row :: struct {
	path:   string,          // owned
	kind:   fs.Kind,
	ranges: []ui.Fuzzy_Range, // owned
	score:  int,
}

// The interface's side (App.deep): the index of the folder searched, the question in flight and the last answer.
Deep_Search :: struct {
	index:         ^Deep_Index,
	serial:        u64,            // the question asked last (an older answer is dropped)
	in_flight:     bool,
	asked:         string,         // owned: the letters of the question asked last
	asked_hidden:  bool,
	asked_version: int,
	rows:          [dynamic]Deep_Row,   // owned: the last answer
	rows_for:      string,         // owned: the letters it answers
}

@(private = "file")
deep_index_release :: proc(x: ^Deep_Index) {
	if sync.atomic_sub(&x.refs, 1) != 1 { return }
	heap := runtime.heap_allocator()
	delete(x.root, heap)
	fs.listing_destroy(&x.list)
	free(x, heap)
}

@(private = "file")
deep_rows_free :: proc(rows: ^[dynamic]Deep_Row) {
	heap := runtime.heap_allocator()
	for r in rows { delete(r.path, heap); delete(r.ranges, heap) }
	clear(rows)
}

// The index let go: the walk stops, the last answer goes. The next question walks again.
deep_reset :: proc(app: ^App) {
	d := &app.deep
	if d.index != nil {
		sync.atomic_store(&d.index.stop, true)
		deep_index_release(d.index)
		d.index = nil
	}
	d.serial += 1   // (an answer still out is for the index let go)
	d.in_flight = false
	deep_rows_free(&d.rows)
	heap := runtime.heap_allocator()
	delete(d.asked, heap)
	delete(d.rows_for, heap)
	d.asked, d.rows_for, d.asked_version = "", "", 0
}

deep_free :: proc(app: ^App) {
	deep_reset(app)
	delete(app.deep.rows)
	app.deep = {}
}

// The rows that answer `query` below `root`, from the last answer (they may answer a few letters before: they stay until
// the new answer comes). `reading`: the walk goes on; `read`: the entries in the index.
deep_rows :: proc(app: ^App, root, query: string) -> (rows: []Deep_Row, reading: bool, read: int) {
	d := &app.deep
	heap := runtime.heap_allocator()
	if d.index != nil && d.index.root != root { deep_reset(app) }
	if query == "" { return nil, false, 0 }
	if d.index == nil {
		x := new(Deep_Index, heap)
		x.root, x.app, x.refs = strings.clone(root, heap), app, 2   // (the interface and the walk)
		d.index = x
		if !tasks.add(&app.pool, deep_walk_run, x) {
			sync.atomic_store(&x.done, true)
			deep_index_release(x)
		}
	}
	x := d.index
	version := sync.atomic_load(&x.version)
	if !d.in_flight && (query != d.asked || app.show_hidden != d.asked_hidden || version != d.asked_version) {
		delete(d.asked, heap)
		d.asked, d.asked_hidden, d.asked_version = strings.clone(query, heap), app.show_hidden, version
		d.serial += 1
		m := new(Deep_Match, heap)
		m^ = {app = app, index = x, query = strings.clone(query, heap), hidden = app.show_hidden, serial = d.serial}
		sync.atomic_add(&x.refs, 1)
		d.in_flight = true
		if !tasks.add(&app.pool, deep_match_run, m) {
			d.in_flight = false
			deep_match_free(m)
		}
	}
	reading = !sync.atomic_load(&x.done)
	// (the walk's batches come every 200 ms: a frame then asks the match again)
	if reading { ui.wake_within(&app.main.state, 200) }
	return d.rows[:], reading, sync.atomic_load(&x.count)
}

////////////////////////////////
// The walk

@(private = "file")
deep_walk_run :: proc(data: rawptr) {
	x := (^Deep_Index)(data)
	defer deep_index_release(x)
	l: fs.Listing
	defer fs.listing_destroy(&l)
	_ = fs.walk(&l, x.root, stop = proc(user: rawptr) -> bool {
		return sync.atomic_load(&(^Deep_Index)(user).stop)
	}, user = x, progress = proc(user: rawptr, batch: ^fs.Listing) {
		x := (^Deep_Index)(user)
		deep_take(x, batch.entries[:])
		fs.listing_destroy(batch)
	})
	// (the walk hands no batch after its last period: what came since is in its own listing)
	sync.mutex_lock(&x.lock)
	given := len(x.list.entries)
	sync.mutex_unlock(&x.lock)
	if given < len(l.entries) { deep_take(x, l.entries[given:]) }
	sync.atomic_store(&x.done, true)
	sync.atomic_add(&x.version, 1)
	if !sync.atomic_load(&x.stop) { _ = ui.post(&x.app.main.state, deep_wake, x.app) }
}

// Entries the walk found, added to the index.
@(private = "file")
deep_take :: proc(x: ^Deep_Index, entries: []fs.Entry) {
	sync.mutex_lock(&x.lock)
	for e in entries {
		if len(x.list.entries) >= DEEP_MAX_ENTRIES { break }
		y := e
		y.name = fs.keep_name(&x.list, e.name)
		append(&x.list.entries, y)
	}
	n := len(x.list.entries)
	sync.mutex_unlock(&x.lock)
	sync.atomic_store(&x.count, n)
	sync.atomic_add(&x.version, 1)
	if n >= DEEP_MAX_ENTRIES { sync.atomic_store(&x.stop, true) }
}

@(private = "file")
deep_wake :: proc(data: rawptr, word: u64) { app_frames((^App)(data)) }

////////////////////////////////
// A match

@(private = "file")
Deep_Match :: struct {
	app:    ^App,
	index:  ^Deep_Index,
	query:  string,
	hidden: bool,
	serial: u64,
	rows:   [dynamic]Deep_Row,
}

@(private = "file")
deep_match_free :: proc(m: ^Deep_Match) {
	heap := runtime.heap_allocator()
	deep_rows_free(&m.rows)
	delete(m.rows)
	delete(m.query, heap)
	deep_index_release(m.index)
	free(m, heap)
}

// Whether `rel` is under a hidden folder, or hidden itself.
@(private = "file")
deep_hidden :: proc(rel: string) -> bool {
	if strings.has_prefix(rel, ".") { return true }
	for i in 0 ..< len(rel) - 1 {
		if fs.is_separator(rel[i]) && rel[i + 1] == '.' { return true }
	}
	return false
}

@(private = "file")
deep_depth :: proc(rel: string) -> int {
	n := 0
	for i in 0 ..< len(rel) { if fs.is_separator(rel[i]) { n += 1 } }
	return n
}

// What `rel` scores for `query` (by its name, or by its path when the query holds a separator); ok false: no match.
@(private = "file")
deep_score :: proc(query, rel: string, by_path: bool, allocator := context.temp_allocator) -> (score: int, ranges: []ui.Fuzzy_Range, ok: bool) {
	hay := by_path ? rel : fs.base(rel)
	score, ranges, ok = ui.fuzzy_score(query, hay, allocator)
	if !ok { return }
	if strings.equal_fold(hay, query) { score += DEEP_EXACT_BONUS }
	score -= deep_depth(rel) * DEEP_DEPTH_COST
	// (the ranges in the name, moved to where the name is in the path the row shows)
	if !by_path {
		at := len(rel) - len(hay)
		for &r in ranges { r[0] += at; r[1] += at }
	}
	return
}

// (on a worker) The index scored for the query: the best DEEP_ROWS, then a relative path that exists first.
@(private = "file")
deep_match_run :: proc(data: rawptr) {
	m := (^Deep_Match)(data)
	x := m.index
	heap := runtime.heap_allocator()
	query := strings.trim_space(m.query)
	by_path := false
	for i in 0 ..< len(query) { if fs.is_separator(query[i]) { by_path = true; break } }
	show_hidden := m.hidden || strings.has_prefix(query, ".")
	Kept :: struct { name: string, kind: fs.Kind, score: int }
	kept := make([dynamic]Kept, 0, DEEP_ROWS + 1, context.temp_allocator)
	worst := min(int)
	if query != "" && !sync.atomic_load(&x.stop) {
		sync.mutex_lock(&x.lock)
		for e in x.list.entries {
			if !show_hidden && deep_hidden(e.name) { continue }
			score: int
			ok: bool
			{
				// (one entry's temporary memory at a time: an index of 400 000 entries scored)
				runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
				score, _, ok = deep_score(query, e.name, by_path)
			}
			if !ok || (len(kept) == DEEP_ROWS && score <= worst) { continue }
			at := len(kept)
			for at > 0 && kept[at - 1].score < score { at -= 1 }
			inject_at(&kept, at, Kept{e.name, e.kind, score})
			if len(kept) > DEEP_ROWS { pop(&kept) }
			if len(kept) == DEEP_ROWS { worst = kept[len(kept) - 1].score }
		}
		// (the kept names copied before the lock goes: the index's arena is the walk's to grow)
		for &k in kept { k.name = strings.clone(k.name, context.temp_allocator) }
		sync.mutex_unlock(&x.lock)
	}
	// a relative path that exists: first, even before the walk reaches it
	exact := ""
	if by_path {
		rel := strings.trim_right(query, "/\\")
		if info, ok := fs.stat(fs.join(x.root, rel, context.temp_allocator)); ok {
			exact = fs.clean(rel, context.temp_allocator)
			_, ranges, _ := ui.fuzzy_score(query, exact, heap)
			append(&m.rows, Deep_Row{path = strings.clone(exact, heap), kind = info.kind, ranges = ranges, score = max(int)})
		}
	}
	for k in kept {
		if k.name == exact { continue }
		score, ranges, _ := deep_score(query, k.name, by_path, heap)
		append(&m.rows, Deep_Row{path = strings.clone(k.name, heap), kind = k.kind, ranges = ranges, score = score})
	}
	if !ui.post(&m.app.main.state, deep_match_done, m) { deep_match_free(m) }
}

@(private = "file")
deep_match_done :: proc(data: rawptr, word: u64) {
	m := (^Deep_Match)(data)
	app := m.app
	d := &app.deep
	defer deep_match_free(m)
	if m.serial != d.serial { return }
	heap := runtime.heap_allocator()
	d.in_flight = false
	deep_rows_free(&d.rows)
	d.rows, m.rows = m.rows, d.rows
	delete(d.rows_for, heap)
	d.rows_for = strings.clone(m.query, heap)
	slice.stable_sort_by(d.rows[:], proc(a, b: Deep_Row) -> bool { return a.score > b.score })
	app_frames(app)
}
