package fs

// Windows: what changes files. CopyFileExW copies (attributes and times included) and reports its progress; a rename
// never replaces (MoveFileExW without MOVEFILE_REPLACE_EXISTING); the trash is the Recycle Bin (IFileOperation, whose
// records the shell's Restore reads, and which says where each item went).

import "base:runtime"
import "core:os"
import "core:strings"
import "core:time"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"

@(private = "file")
COPY_FILE_FAIL_IF_EXISTS :: 0x1
@(private = "file")
PROGRESS_CONTINUE :: 0
@(private = "file")
PROGRESS_CANCEL :: 1
@(private = "file")
ERROR_ALREADY_EXISTS :: 183
@(private = "file")
ERROR_FILE_EXISTS :: 80
@(private = "file")
ERROR_NOT_SAME_DEVICE :: 17
@(private = "file")
ERROR_DISK_FULL :: 112
@(private = "file")
ERROR_REQUEST_ABORTED :: 1235
@(private = "file")
ERROR_DIR_NOT_EMPTY :: 145
@(private = "file")
SYMBOLIC_LINK_FLAG_DIRECTORY :: 0x1
@(private = "file")
SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE :: 0x2

@(private = "file")
Copy_Progress :: #type proc "system" (total, transferred, stream_size, stream_transferred: i64, stream: win.DWORD, reason: win.DWORD, src, dst: win.HANDLE, data: rawptr) -> win.DWORD

@(default_calling_convention = "system", private = "file")
foreign kernel32 {
	CopyFileExW :: proc(from, to: win.LPCWSTR, progress: Copy_Progress, data: rawptr, cancel: ^win.BOOL, flags: win.DWORD) -> win.BOOL ---
	CreateSymbolicLinkW :: proc(link, target: win.LPCWSTR, flags: win.DWORD) -> win.BOOLEAN ---
	GetFinalPathNameByHandleW :: proc(file: win.HANDLE, path: win.LPWSTR, size, flags: win.DWORD) -> win.DWORD ---
}

@(private = "file")
op_error :: proc(code: win.DWORD) -> Error {
	switch code {
	case 0:                                                  return .None
	case win.ERROR_FILE_NOT_FOUND, win.ERROR_PATH_NOT_FOUND: return .Not_Found
	case win.ERROR_ACCESS_DENIED:                            return .Denied
	case ERROR_ALREADY_EXISTS, ERROR_FILE_EXISTS, ERROR_DIR_NOT_EMPTY: return .Exists
	case ERROR_NOT_SAME_DEVICE:                              return .Cross_Volume
	case ERROR_DISK_FULL:                                    return .No_Space
	case ERROR_REQUEST_ABORTED:                              return .Cancelled
	}
	return .Other
}

@(private = "file")
wide :: proc(path: string) -> win.LPCWSTR { return win.utf8_to_wstring(path, context.temp_allocator) }

@(private = "file")
Copy_State :: struct {
	p:    ^Progress,
	seen: i64,
	ctx:  runtime.Context,
}

@(private = "file")
copy_progress :: proc "system" (total, transferred, stream_size, stream_transferred: i64, stream: win.DWORD, reason: win.DWORD, src, dst: win.HANDLE, data: rawptr) -> win.DWORD {
	st := (^Copy_State)(data)
	context = st.ctx
	if st.p.on_bytes != nil && transferred > st.seen { st.p.on_bytes(st.p.user, transferred - st.seen) }
	st.seen = transferred
	if st.p.cancelled != nil && st.p.cancelled(st.p.user) { return PROGRESS_CANCEL }
	return PROGRESS_CONTINUE
}

copy_file_native :: proc(from, to: string, p: ^Progress = nil) -> Error {
	if p == nil {
		if !CopyFileExW(wide(from), wide(to), nil, nil, nil, COPY_FILE_FAIL_IF_EXISTS) { return op_error(win.GetLastError()) }
		return .None
	}
	st := Copy_State{p = p, ctx = context}
	if !CopyFileExW(wide(from), wide(to), copy_progress, &st, nil, COPY_FILE_FAIL_IF_EXISTS) { return op_error(win.GetLastError()) }
	return .None
}

// A symbolic link made again at `to`, with the same target (Developer Mode or the privilege: else .Denied).
copy_link :: proc(from, to: string) -> Error {
	target, ok := link_target(from)
	if !ok { return .Other }
	info, _ := stat(from)
	flags: win.DWORD = SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
	if info.kind == .Directory { flags |= SYMBOLIC_LINK_FLAG_DIRECTORY }
	if !bool(CreateSymbolicLinkW(wide(to), wide(target), flags)) { return op_error(win.GetLastError()) }
	return .None
}

// What a link points to: the final path of what it opens.
@(private = "file")
link_target :: proc(path: string) -> (string, bool) {
	h := win.CreateFileW(wide(path), 0, win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE, nil, win.OPEN_EXISTING, win.FILE_FLAG_BACKUP_SEMANTICS, nil)
	if h == win.INVALID_HANDLE_VALUE { return "", false }
	defer win.CloseHandle(h)
	buf: [win.MAX_PATH * 4]u16
	n := GetFinalPathNameByHandleW(h, &buf[0], len(buf), 0)
	if n == 0 || int(n) >= len(buf) { return "", false }
	s, _ := win.wstring_to_utf8(cstring16(&buf[0]), int(n), context.temp_allocator)
	return strings.trim_prefix(s, "\\\\?\\"), true
}

make_folder_native :: proc(path: string) -> Error {
	if !win.CreateDirectoryW(wide(path), nil) { return op_error(win.GetLastError()) }
	return .None
}

// An empty file at `path`, never over something (.Exists when the name is taken).
make_file_native :: proc(path: string) -> Error {
	h := win.CreateFileW(wide(path), win.GENERIC_WRITE, 0, nil, win.CREATE_NEW, win.FILE_ATTRIBUTE_NORMAL, nil)
	if h == win.INVALID_HANDLE_VALUE { return op_error(win.GetLastError()) }
	win.CloseHandle(h)
	return .None
}

// Renames `from` to `to`, never over something: .Exists when the name is taken, .Cross_Volume when it is on another
// volume.
// (a file the shell or an antivirus reads for a moment refuses to move: tried again a few times, as Explorer does)
rename_native :: proc(from, to: string) -> Error {
	for attempt in 0 ..< 10 {
		if win.MoveFileExW(wide(from), wide(to), 0) { return .None }
		e := win.GetLastError()
		if e != win.ERROR_SHARING_VIOLATION && e != win.ERROR_ACCESS_DENIED || attempt == 9 { return op_error(e) }
		time.sleep(20 * time.Millisecond)
	}
	return .Other
}

// A file, a link or an empty folder.
remove_native :: proc(path: string) -> Error {
	info, ok := stat(path)
	if !ok { return .Not_Found }
	if info.kind == .Directory {
		if !win.RemoveDirectoryW(wide(path)) { return op_error(win.GetLastError()) }
		return .None
	}
	if !win.DeleteFileW(wide(path)) { return op_error(win.GetLastError()) }
	return .None
}

exists_native :: proc(path: string) -> bool {
	return win.GetFileAttributesW(wide(path)) != win.INVALID_FILE_ATTRIBUTES
}

// IFileOperation (shobjidl_core.h), which core:sys/windows does not declare: only the methods trash_native calls are
// typed, the others keep their places in the table.
@(private = "file")
IFileOperation :: struct #raw_union {
	#subtype IUnknown: win.IUnknown,
	using Vtbl: ^IFileOperationVtbl,
}
@(private = "file")
IFileOperationVtbl :: struct {
	using IUnknownVtbl: win.IUnknownVtbl,
	Advise:                 rawptr,
	Unadvise:               rawptr,
	SetOperationFlags:      proc "system" (this: ^IFileOperation, flags: win.DWORD) -> win.HRESULT,
	SetProgressMessage:     rawptr,
	SetProgressDialog:      rawptr,
	SetProperties:          rawptr,
	SetOwnerWindow:         rawptr,
	ApplyPropertiesToItem:  rawptr,
	ApplyPropertiesToItems: rawptr,
	RenameItem:             rawptr,
	RenameItems:            rawptr,
	MoveItem:               rawptr,
	MoveItems:              rawptr,
	CopyItem:               rawptr,
	CopyItems:              rawptr,
	DeleteItem:             proc "system" (this: ^IFileOperation, item: ^win.IShellItem, sink: ^win.IFileOperationProgressSink) -> win.HRESULT,
	DeleteItems:            rawptr,
	NewItem:                rawptr,
	PerformOperations:      proc "system" (this: ^IFileOperation) -> win.HRESULT,
	GetAnyOperationsAborted: proc "system" (this: ^IFileOperation, aborted: ^win.BOOL) -> win.HRESULT,
}

@(private = "file")
CLSID_FileOperation := &win.GUID{0x3ad05575, 0x8857, 0x4850, {0x92, 0x77, 0x11, 0xb8, 0x5b, 0xdb, 0x8e, 0x09}}
@(private = "file")
IID_IFileOperation := &win.GUID{0x947aab5f, 0x0a5c, 0x4c13, {0xb4, 0xd6, 0x4b, 0xf7, 0x83, 0x6f, 0xc9, 0xf8}}
@(private = "file")
IID_IFileOperationProgressSink := &win.GUID{0x04b0f1a7, 0x9490, 0x44bc, {0x96, 0xe1, 0x42, 0x96, 0xa3, 0x12, 0x52, 0xe2}}

// No UI at all, to the Recycle Bin (FOFX_RECYCLEONDELETE: FOF_ALLOWUNDO alone is not enough for IFileOperation).
@(private = "file")
TRASH_FLAGS :: win.FOF_NO_UI | win.FOF_ALLOWUNDO | 0x00080000

// The sink of one delete: it keeps the path of the item the Recycle Bin made (CoTaskMem, the caller frees it). It lives
// on the caller's stack for the length of PerformOperations, so its counts are not kept.
@(private = "file")
Trash_Sink :: struct {
	using sink: win.IFileOperationProgressSink,
	created:    win.LPWSTR,
	result:     win.HRESULT,
}

@(private = "file")
trash_sink_vtbl := win.IFileOperationProgressSinkVtbl{
	QueryInterface = proc "system" (this: ^win.IUnknown, riid: win.REFIID, out: ^rawptr) -> win.HRESULT {
		if riid^ == win.IUnknown_UUID^ || riid^ == IID_IFileOperationProgressSink^ { out^ = this; return win.S_OK }
		out^ = nil
		return transmute(win.HRESULT)u32(win.E_NOINTERFACE)
	},
	AddRef  = proc "system" (this: ^win.IUnknown) -> win.ULONG { return 1 },
	Release = proc "system" (this: ^win.IUnknown) -> win.ULONG { return 1 },
	StartOperations  = proc "system" (this: ^win.IFileOperationProgressSink) -> win.HRESULT { return win.S_OK },
	FinishOperations = proc "system" (this: ^win.IFileOperationProgressSink, hr: win.HRESULT) -> win.HRESULT { return win.S_OK },
	PreRenameItem    = proc "system" (this: ^win.IFileOperationProgressSink, flags: win.DWORD, item: ^win.IShellItem, name: win.LPCWSTR) -> win.HRESULT { return win.S_OK },
	PostRenameItem   = proc "system" (this: ^win.IFileOperationProgressSink, flags: win.DWORD, item: ^win.IShellItem, name: win.LPCWSTR, hr: win.HRESULT, created: ^win.IShellItem) -> win.HRESULT { return win.S_OK },
	PreMoveItem      = proc "system" (this: ^win.IFileOperationProgressSink, flags: win.DWORD, item, to: ^win.IShellItem, name: win.LPCWSTR) -> win.HRESULT { return win.S_OK },
	PostMoveItem     = proc "system" (this: ^win.IFileOperationProgressSink, flags: win.DWORD, item, to: ^win.IShellItem, name: win.LPCWSTR, hr: win.HRESULT, created: ^win.IShellItem) -> win.HRESULT { return win.S_OK },
	PreCopyItem      = proc "system" (this: ^win.IFileOperationProgressSink, flags: win.DWORD, item, to: ^win.IShellItem, name: win.LPCWSTR) -> win.HRESULT { return win.S_OK },
	PostCopyItem     = proc "system" (this: ^win.IFileOperationProgressSink, flags: win.DWORD, item, to: ^win.IShellItem, name: win.LPCWSTR, hr: win.HRESULT, created: ^win.IShellItem) -> win.HRESULT { return win.S_OK },
	PreDeleteItem    = proc "system" (this: ^win.IFileOperationProgressSink, flags: win.DWORD, item: ^win.IShellItem) -> win.HRESULT { return win.S_OK },
	PostDeleteItem   = proc "system" (this: ^win.IFileOperationProgressSink, flags: win.DWORD, item: ^win.IShellItem, hr: win.HRESULT, created: ^win.IShellItem) -> win.HRESULT {
		s := (^Trash_Sink)(this)
		s.result = hr
		// (no new item: deleted for good, the drive has no Recycle Bin)
		if win.SUCCEEDED(hr) && created != nil && s.created == nil { _ = created->GetDisplayName(.FILESYSPATH, &s.created) }
		return win.S_OK
	},
	PreNewItem     = proc "system" (this: ^win.IFileOperationProgressSink, flags: win.DWORD, to: ^win.IShellItem, name: win.LPCWSTR) -> win.HRESULT { return win.S_OK },
	PostNewItem    = proc "system" (this: ^win.IFileOperationProgressSink, flags: win.DWORD, to: ^win.IShellItem, name, template: win.LPCWSTR, attributes: win.DWORD, hr: win.HRESULT, item: ^win.IShellItem) -> win.HRESULT { return win.S_OK },
	UpdateProgress = proc "system" (this: ^win.IFileOperationProgressSink, total, done: win.UINT) -> win.HRESULT { return win.S_OK },
	ResetTimer     = proc "system" (this: ^win.IFileOperationProgressSink) -> win.HRESULT { return win.S_OK },
	PauseTimer     = proc "system" (this: ^win.IFileOperationProgressSink) -> win.HRESULT { return win.S_OK },
	ResumeTimer    = proc "system" (this: ^win.IFileOperationProgressSink) -> win.HRESULT { return win.S_OK },
}

// To the Recycle Bin. `in_trash`: where the Recycle Bin put it (its $R file), for untrash, as the shell's operation
// says it; "" when it made none (a drive without a Recycle Bin deletes for good).
trash_native :: proc(path: string, allocator := context.allocator) -> (in_trash: string, e: Error) {
	if !exists(path) { return "", .Not_Found }
	// (an apartment of this thread for the operation; one already there in another mode is fine)
	joined := win.CoInitializeEx(nil, .APARTMENTTHREADED)
	defer if win.SUCCEEDED(joined) { win.CoUninitialize() }
	op: ^IFileOperation
	if !win.SUCCEEDED(win.CoCreateInstance(CLSID_FileOperation, nil, win.CLSCTX_ALL, IID_IFileOperation, (^rawptr)(&op))) { return "", .Other }
	defer op->Release()
	item: ^win.IShellItem
	if !win.SUCCEEDED(win.SHCreateItemFromParsingName(wide(path), nil, win.IID_IShellItem, (^rawptr)(&item))) { return "", .Not_Found }
	defer item->Release()
	sink := Trash_Sink{sink = {Vtbl = &trash_sink_vtbl}}
	defer if sink.created != nil { win.CoTaskMemFree(sink.created) }
	if !win.SUCCEEDED(op->SetOperationFlags(TRASH_FLAGS)) || !win.SUCCEEDED(op->DeleteItem(item, &sink)) { return "", .Other }
	hr := op->PerformOperations()
	aborted: win.BOOL
	_ = op->GetAnyOperationsAborted(&aborted)
	if !win.SUCCEEDED(hr) || !win.SUCCEEDED(sink.result) || bool(aborted) { return "", .Other }
	if sink.created == nil { return "", .None }
	s, err := win.wstring_to_utf8(cstring16(sink.created), -1, allocator)
	return err == nil ? s : "", .None
}

// Puts back an item of the Recycle Bin (its $R path, as trash gave it): renamed to where its $I record says it was (or
// to `to`, a name of its own beside it), the record removed. Exists: something is there now.
untrash :: proc(in_trash: string, allocator := context.allocator, to := "") -> (original: string, e: Error) {
	record := trash_record(in_trash)
	if record == "" { return "", .Other }
	from, _, ok := recycle_record(record)
	if !ok { return "", .Not_Found }
	target := to != "" ? to : from
	if exists(target) { return "", .Exists }
	_ = os.make_directory_all(parent(target))   // (its folder may have gone since)
	if err := rename_native(in_trash, target); err != .None { return "", err }
	_ = remove_native(record)
	return strings.clone(target, allocator), .None
}

// Where untrash puts an item of the Recycle Bin back, as its $I record says.
trash_origin :: proc(in_trash: string, allocator := context.temp_allocator) -> (original: string, ok: bool) {
	record := trash_record(in_trash)
	if record == "" { return }
	from, _, rok := recycle_record(record)
	if !rok { return }
	return strings.clone(from, allocator), true
}

// The $I record beside an item of the Recycle Bin (its $R path); "": not one.
trash_record :: proc(in_trash: string, allocator := context.temp_allocator) -> string {
	name := base(in_trash)
	if !strings.has_prefix(name, "$R") { return "" }
	return join(parent(in_trash), strings.concatenate({"$I", name[2:]}, context.temp_allocator), allocator)
}

// What a $I record of the Recycle Bin says (recycle.odin): the item's path before, and when it was trashed (ns since
// 1970). Temp memory.
@(private)
recycle_record :: proc(record: string) -> (from: string, at: i64, ok: bool) {
	data, err := os.read_entire_file(record, context.temp_allocator)
	if err != nil { return }
	r, rok := recycle_record_parse(data)
	return r.from, r.at, rok
}

// Whether `a` and `b` are on one volume (their drive or share is the same).
same_volume :: proc(a, b: string) -> bool {
	// (as on Linux: a path that is not there is on no volume)
	if !exists(a) || !exists(b) { return false }
	ra, rb := root_length(a), root_length(b)
	if ra == 0 || ra != rb { return false }
	return strings.equal_fold(a[:ra], b[:rb])
}
