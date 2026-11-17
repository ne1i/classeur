package classeur

// How an entry reads in a row: its size, its date, its type, its icon.

import "core:fmt"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"
import "gt:i18n"
import "gt:timefmt"
import "gt:ui"
import "fs"

// How the dates read (files.date_format). The words and their order are the language's (gt:timefmt).
Date_Format :: enum u8 {
	ISO,              // "2026-11-09 21:40"
	Relative,         // "today 21:40", "yesterday 21:40", "Monday 21:40", else "Nov 5, 21:40" ("Dec 31 2025, 21:40")
	Day_Month_Year,   // "Nov 9 2026 21:40"
}

// A time in the local time (UTC when the time zone is not known).
local_datetime :: proc(tz: ^datetime.TZ_Region, ns: i64) -> (dt: datetime.DateTime, ok: bool) {
	dt = time.time_to_datetime(time.Time{_nsec = ns}) or_return
	if tz != nil {
		if local, lok := timezone.datetime_to_tz(dt, tz); lok { dt = local }
	}
	return dt, true
}

// A date in the local time, in the person's format.
date_text :: proc(app: ^App, ns: i64, allocator := context.temp_allocator) -> string {
	if ns == 0 { return "" }
	dt, ok := local_datetime(app.tz, ns)
	if !ok { return "" }
	today: datetime.Date
	if app.settings.date_format == .Relative {
		// (today read once a frame, not for each row shown)
		if app.today_frame != app.frame || app.today.year == 0 {
			app.today_frame = app.frame
			if now, nok := local_datetime(app.tz, time.now()._nsec); nok {
				app.today = now.date
				// (an idle window draws no frame: woken just past midnight, its "Today" becomes "Yesterday")
				ui.wake_within(&app.main.state, int(ms_to_midnight(now.time)) + MIDNIGHT_MARGIN_MS)
			}
		}
		today = app.today
	}
	return date_format_text(dt, today, app.settings.date_format, allocator)
}

// How long past midnight the window wakes (the clock read then is surely on the new day).
MIDNIGHT_MARGIN_MS :: 50

// The milliseconds from a local time of day to the next local midnight (a day of 24 hours: a change of the clock
// between them is not counted).
ms_to_midnight :: proc(at: datetime.Time) -> i64 {
	past := (i64(at.hour) * 3600 + i64(at.minute) * 60 + i64(at.second)) * 1000 + i64(at.nano) / 1_000_000
	return max(24 * 3600 * 1000 - past, 1)
}

// `dt` (a local time) in `format`; `today` is what Relative counts from.
date_format_text :: proc(dt: datetime.DateTime, today: datetime.Date, format: Date_Format, allocator := context.temp_allocator) -> string {
	ms, ok := wall_ms(dt)
	if !ok { return "" }
	switch format {
	case .ISO:
	case .Day_Month_Year:
		return fmt.aprintf("%s %s", timefmt.date(ms, 0, year = true), timefmt.clock(ms, 0), allocator = allocator)
	case .Relative:
		// (today's midnight: moment reads its day and its year alone)
		now, now_ok := wall_ms({date = today})
		return timefmt.moment(ms, now_ok ? now : 0, 0, weekdays = true, allocator = allocator)
	}
	return timefmt.iso_date(ms, 0, with_clock = true, allocator = allocator)
}

// A local time as milliseconds whose UTC fields read as its own, for timefmt with an offset of 0. The time zone's
// region converts each date with the offset of its own day: timefmt.local_offset_minutes is today's alone, and a date
// across a change of the clock (summer time) would read an hour off.
@(private = "file")
wall_ms :: proc(dt: datetime.DateTime) -> (ms: f64, ok: bool) {
	plain := dt
	plain.tz = nil   // (its fields are the wall clock's already)
	t := time.compound_to_time(plain) or_return
	return f64(time.to_unix_nanoseconds(t)) / 1e6, true
}

// What an entry is: the system's name of its type when it is known (type_names.odin), else its extension's.
type_text :: proc(app: ^App, e: fs.Entry, allocator := context.temp_allocator) -> string {
	switch e.kind {
	case .Directory:   return .Link in e.flags ? i18n.tr("Folder link") : i18n.tr("Folder")
	case .Broken_Link: return i18n.tr("Broken link")
	case .Other:       return i18n.tr("Special")
	case .File:
	}
	ext := fs.extension(fs.base(e.name))   // (a search's rows are named by their path below the folder)
	if ext == "" { return .Executable in e.flags ? i18n.tr("Program") : i18n.tr("File") }
	if name := type_name(app, ext); name != "" { return strings.clone(name, allocator) }
	return fmt.aprintf(i18n.tr("%s File"), strings.to_upper(ext, context.temp_allocator), allocator = allocator)
}


// "984", "7.3K", "12K", "1.2M": a count in a narrow column.
count_text :: proc(n: i64, allocator := context.temp_allocator) -> string {
	switch {
	case n < 1000:      return fmt.aprintf("%d", n, allocator = allocator)
	case n < 10_000:    return fmt.aprintf("%sK", i18n.decimal(f64(n) / 1000, 1), allocator = allocator)
	case n < 1_000_000: return fmt.aprintf("%dK", n / 1000, allocator = allocator)
	}
	return fmt.aprintf("%sM", i18n.decimal(f64(n) / 1_000_000, 1), allocator = allocator)
}
