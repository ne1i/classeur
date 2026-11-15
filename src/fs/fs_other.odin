#+build !windows
#+build !linux
package fs

// Another system (macOS first): core:os reads a folder and its entries. It costs a stat per entry and builds each
// path: slower than fs_linux.odin, but correct until this system has its own reader.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:time"

@(private = "file")
os_error :: proc(e: os.Error) -> Error {
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

@(private = "file")
info_kind :: proc(t: os.File_Type) -> Kind {
	#partial switch t {
	case .Regular:   return .File
	case .Directory: return .Directory
	}
	return .Other
}

@(private = "file")
time_ns :: proc(t: time.Time) -> i64 { return time.to_unix_nanoseconds(t) }

// The kind, size, time and flags of `path` (links: their target's, flagged).
@(private = "file")
stat_entry :: proc(path: string, e: ^Entry) -> bool {
	fi, err := os.lstat(path, context.temp_allocator)
	if err != nil {
		e.kind = .Other
		return false
	}
	if fi.type == .Symlink {
		e.flags += {.Link}
		target, terr := os.stat(path, context.temp_allocator)
		if terr != nil {
			e.kind = .Broken_Link
			return true
		}
		fi = target
	}
	e.kind = info_kind(fi.type)
	e.mtime = time_ns(fi.modification_time)
	if e.kind == .File { e.size = fi.size }
	if e.kind == .File && (fi.mode & os.Permissions_Execute_All) != {} { e.flags += {.Executable} }
	if (fi.mode & os.Permissions_Write_All) == {} { e.flags += {.Read_Only} }
	return true
}

@(private)
list_native :: proc(l: ^Listing, path: string) -> Error {
	infos, err := os.read_all_directory_by_path(path, context.temp_allocator)
	if err != nil { return os_error(err) }
	for fi in infos {
		if fi.name == "." || fi.name == ".." { continue }
		e := Entry{size = -1}
		stat_entry(fi.fullpath, &e)
		if len(fi.name) > 0 && fi.name[0] == '.' { e.flags += {.Hidden} }
		e.name = keep_name(l, fi.name)
		append(&l.entries, e)
	}
	return .None
}

stat_native :: proc(path: string) -> (info: Info, ok: bool) {
	e := Entry{size = -1}
	if !stat_entry(path, &e) { return }
	return Info{kind = e.kind, size = e.size, mtime = e.mtime, flags = e.flags}, true
}

space :: proc(path: string) -> (s: Space, ok: bool) {
	st: posix.statvfs_t
	if posix.statvfs(strings.clone_to_cstring(path, context.temp_allocator), &st) != .OK { return }
	unit := st.f_frsize > 0 ? i64(st.f_frsize) : i64(st.f_bsize)
	return Space{free = i64(st.f_bavail) * unit, total = i64(st.f_blocks) * unit}, true
}

// Its birth and access times and its permissions; the owner is not read here yet.
properties_native :: proc(path: string) -> (p: Properties, ok: bool) {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil { return }
	p.created = time_ns(fi.creation_time)
	p.accessed = time_ns(fi.access_time)
	bits := transmute(u32)fi.mode & 0o777
	b := strings.builder_make(context.temp_allocator)
	letters := "rwx"
	for i in 0 ..< 9 {
		on := bits & (1 << u32(8 - i)) != 0
		strings.write_byte(&b, on ? letters[i % 3] : '-')
	}
	p.permissions = fmt.tprintf("%s (%o)", strings.to_string(b), bits)
	return p, true
}
