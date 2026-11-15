#+build !windows
#+build !linux
package fs

// Another system (macOS first): what changes files, through core:os. A file is copied by read and write, in steps
// that report their progress; its mode and modification time go with it.

import "core:os"
import "core:sys/posix"

@(private = "file")
COPY_BUFFER :: 1024 * 1024

@(private = "file")
op_error :: proc(e: os.Error) -> Error {
	if e == nil { return .None }
	#partial switch v in e {
	case os.General_Error:
		#partial switch v {
		case .Not_Exist:    return .Not_Found
		case .Exist:        return .Exists
		case .Invalid_Dir:  return .Not_A_Folder
		}
	case os.Platform_Error:
		#partial switch posix.Errno(v) {
		case .ENOENT:                  return .Not_Found
		case .EACCES, .EPERM, .EROFS:  return .Denied
		case .ENOTDIR:                 return .Not_A_Folder
		case .EEXIST, .ENOTEMPTY:      return .Exists
		case .EXDEV:                   return .Cross_Volume
		case .ENOSPC, .EDQUOT:         return .No_Space
		}
	}
	return .Other
}

copy_file_native :: proc(from, to: string, p: ^Progress = nil) -> Error {
	src, oerr := os.open(from)
	if oerr != nil { return op_error(oerr) }
	defer os.close(src)
	info, serr := os.fstat(src, context.temp_allocator)
	if serr != nil { return op_error(serr) }
	mode := info.mode & os.Permissions_All
	// (Excl: a copy never goes over a file; the owner's write bit until the end, given back as it was)
	dst, cerr := os.open(to, {.Write, .Create, .Excl}, mode | {.Write_User})
	if cerr != nil { return op_error(cerr) }
	ok := false
	defer if !ok { os.close(dst); os.remove(to) }

	buf := make([]u8, COPY_BUFFER, context.temp_allocator)
	for {
		if p != nil && p.cancelled != nil && p.cancelled(p.user) { return .Cancelled }
		n, rerr := os.read(src, buf)
		if n == 0 { break }
		if rerr != nil && rerr != .EOF { return op_error(rerr) }
		if _, werr := os.write(dst, buf[:n]); werr != nil { return op_error(werr) }
		if p != nil && p.on_bytes != nil { p.on_bytes(p.user, i64(n)) }
	}
	if e := os.close(dst); e != nil {
		os.remove(to)
		ok = true
		return op_error(e)
	}
	ok = true
	if .Write_User not_in mode { os.change_mode(to, mode) }
	os.change_times(to, info.access_time, info.modification_time)
	return .None
}

// A symbolic link made again at `to`, with the same target.
copy_link :: proc(from, to: string) -> Error {
	target, err := os.read_link(from, context.temp_allocator)
	if err != nil { return op_error(err) }
	return op_error(os.symlink(target, to))
}

make_folder_native :: proc(path: string) -> Error {
	return op_error(os.make_directory(path))
}

// An empty file at `path`, never over something (.Exists when the name is taken).
make_file_native :: proc(path: string) -> Error {
	f, err := os.open(path, {.Write, .Create, .Excl}, {.Read_User, .Write_User, .Read_Group, .Read_Other})
	if err != nil { return op_error(err) }
	os.close(f)
	return .None
}

// Renames `from` to `to`, never over something: .Exists when the name is taken, .Cross_Volume when it is on another
// volume. (POSIX has no rename that refuses a name taken: a check first, which another program can race.)
rename_native :: proc(from, to: string) -> Error {
	if exists_native(to) { return .Exists }
	return op_error(os.rename(from, to))
}

// A file, a link or an empty folder.
remove_native :: proc(path: string) -> Error {
	return op_error(os.remove(path))
}

// Whether something is at `path` (a broken link counts).
exists_native :: proc(path: string) -> bool {
	_, err := os.lstat(path, context.temp_allocator)
	return err == nil
}

// Whether `a` and `b` are on one volume (a move between them is a rename).
// (a link is followed: a bookmark that links to another volume is that volume)
same_volume :: proc(a, b: string) -> bool {
	sa, ea := os.stat(a, context.temp_allocator)
	if ea != nil { return false }
	sb, eb := os.stat(b, context.temp_allocator)
	if eb != nil { return false }
	return sa.device == sb.device
}
