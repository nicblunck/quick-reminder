import Foundation

/// Pulls a due date, a clock time and a priority out of a free-text capture line.
///
/// Relative expressions ("tomorrow", "friday", "in 3 days", "5pm") are resolved
/// here against an injected `now`, which is what makes the whole thing testable.
/// Absolute dates ("aug 20", "12/3") fall through to `NSDataDetector`, which
/// already handles far more formats than is worth reimplementing.
///
/// `#hashtags` are deliberately left in the title: EventKit cannot write real
/// Reminders tags, so they survive as searchable text.
enum ReminderParser {

    private static let priorityRegex = regex(#"(?<=^|\s)(!{1,3})(?=\s|$)"#)
    private static let relativeOffsetRegex =
        regex(#"\bin\s+(\d+)\s+(minutes|minute|mins|min|hours|hour|hrs|hr|days|day|weeks|week|months|month)\b"#)
    private static let namedDayRegex =
        regex(#"\b(today|tonight|tomorrow|tmrw|tmr|tmw|eod|next\s+week|next\s+month)\b"#)
    private static let weekdayRegex =
        regex(#"\b(next\s+)?(monday|mondays|mon|tuesday|tuesdays|tues|tue|wednesday|wednesdays|weds|wed|thursday|thursdays|thurs|thur|thu|friday|fridays|fri|saturday|saturdays|sat|sunday|sundays|sun)\b"#)
    private static let timeRegexes = [
        regex(#"\b(?:at\s+|@\s*)?(\d{1,2}):(\d{2})\s*(am|pm|a\.m\.|p\.m\.)\b"#),   // 5:30pm
        regex(#"\b(?:at\s+|@\s*)?(\d{1,2})\s*(am|pm|a\.m\.|p\.m\.)\b"#),           // 5pm
        regex(#"\b(?:at\s+|@\s*)(\d{1,2}):(\d{2})\b"#),                            // at 17:00
        regex(#"\b(\d{1,2}):(\d{2})\b"#),                                          // 17:00
        regex(#"\b(noon|midday|midnight)\b"#),                                     // noon
        regex(#"\b(?:at\s+|@\s*)(\d{1,2})\b"#),                                    // at 5  (ambiguous)
    ]
    private static let danglingPrepositionRegex =
        regex(#"\s*\b(on|at|by|due|before|@)\s*$"#)
    private static let leadingPrepositionRegex =
        regex(#"^\s*\b(on|at|by|due|before)\b\s*"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals authored here; a failure is a programmer error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    // MARK: - Entry point

    /// - Parameter detectDates: set false to re-parse with date detection off,
    ///   which is how "that wasn't a date" (dismissing the chip) puts the words
    ///   back into the title instead of silently swallowing them.
    static func parse(
        _ input: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        detectDates: Bool = true
    ) -> ParseResult {
        var result = ParseResult()
        let text = input as NSString
        var consumed: [NSRange] = []

        // 1. Priority — the last standalone run of "!" wins.
        if let match = priorityRegex.matches(in: input, range: text.fullRange).last {
            let bangs = text.substring(with: match.range(at: 1))
            result.priority = ReminderPriority(bangCount: bangs.count)
            result.prioritySourceText = bangs
            consumed.append(match.range)
        }

        // 2. Date and time.
        let searchable = maskedString(text, excluding: consumed)
        if detectDates,
           let dateHit = extractDate(from: searchable, original: text, now: now, calendar: calendar) {
            result.dueDate = dateHit.date
            result.hasTime = dateHit.hasTime
            result.dueSourceText = dateHit.sourceText
            consumed.append(contentsOf: dateHit.ranges)
        }

        result.cleanedTitle = cleanedTitle(from: text, removing: consumed)
        return result
    }

    // MARK: - Date extraction

    private struct DateHit {
        var date: Date
        var hasTime: Bool
        var sourceText: String
        var ranges: [NSRange]
    }

    private static func extractDate(
        from searchable: String,
        original: NSString,
        now: Date,
        calendar: Calendar
    ) -> DateHit? {
        let range = (searchable as NSString).fullRange

        // "in 20 minutes" / "in 3 days" resolves to an instant on its own.
        if let match = relativeOffsetRegex.firstMatch(in: searchable, range: range),
           let amount = Int((searchable as NSString).substring(with: match.range(at: 1))) {
            let unit = (searchable as NSString).substring(with: match.range(at: 2)).lowercased()
            if let hit = resolveOffset(amount: amount, unit: unit, now: now, calendar: calendar) {
                let source = original.substring(with: match.range)
                if hit.carriesTime {
                    return DateHit(date: hit.date, hasTime: true, sourceText: source, ranges: [match.range])
                }
                // A day-granularity offset can still be paired with "at 5pm".
                return combine(
                    dayStart: calendar.startOfDay(for: hit.date),
                    dayRange: match.range,
                    daySource: source,
                    impliedTime: nil,
                    searchable: searchable,
                    original: original,
                    now: now,
                    calendar: calendar
                )
            }
        }

        // Named days: today / tonight / tomorrow / eod / next week.
        if let match = namedDayRegex.firstMatch(in: searchable, range: range) {
            let token = (searchable as NSString).substring(with: match.range)
                .lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let startToday = calendar.startOfDay(for: now)
            var dayStart = startToday
            var implied: TimeOfDay?

            switch token {
            case "today": break
            case "tonight": implied = TimeOfDay(hour: 20, minute: 0, isAmbiguous: false)
            case "eod": implied = TimeOfDay(hour: 17, minute: 0, isAmbiguous: false)
            case "tomorrow", "tmrw", "tmr", "tmw":
                dayStart = calendar.date(byAdding: .day, value: 1, to: startToday) ?? startToday
            case "next week":
                dayStart = calendar.date(byAdding: .day, value: 7, to: startToday) ?? startToday
            case "next month":
                dayStart = calendar.date(byAdding: .month, value: 1, to: startToday) ?? startToday
            default: break
            }

            return combine(
                dayStart: dayStart,
                dayRange: match.range,
                daySource: original.substring(with: match.range),
                impliedTime: implied,
                searchable: searchable,
                original: original,
                now: now,
                calendar: calendar
            )
        }

        // Weekday names. Bare "friday" means today when today is Friday;
        // "next friday" always skips to the following week.
        if let match = weekdayRegex.firstMatch(in: searchable, range: range) {
            let name = (searchable as NSString).substring(with: match.range(at: 2)).lowercased()
            if let weekday = weekdayNumber(for: name) {
                let startToday = calendar.startOfDay(for: now)
                var target: Date
                if calendar.component(.weekday, from: now) == weekday {
                    target = startToday
                } else {
                    var comps = DateComponents()
                    comps.weekday = weekday
                    target = calendar.nextDate(
                        after: startToday, matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents
                    ) ?? startToday
                }
                if match.range(at: 1).location != NSNotFound {
                    target = calendar.date(byAdding: .day, value: 7, to: target) ?? target
                }
                return combine(
                    dayStart: target,
                    dayRange: match.range,
                    daySource: original.substring(with: match.range),
                    impliedTime: nil,
                    searchable: searchable,
                    original: original,
                    now: now,
                    calendar: calendar
                )
            }
        }

        // A bare time with no day: today, rolling to tomorrow if already past.
        if let time = extractTime(from: searchable, excluding: nil) {
            let startToday = calendar.startOfDay(for: now)
            var date = apply(time: time.value, to: startToday, now: now, calendar: calendar)
            if date <= now {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
            return DateHit(
                date: date,
                hasTime: true,
                sourceText: original.substring(with: time.range),
                ranges: [time.range]
            )
        }

        // Absolute dates ("aug 20", "12/3/2026") — let the system handle the formats.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let match = detector.firstMatch(in: searchable, range: range),
           let date = match.date {
            // `NSTextCheckingResult.timeIsSignificant` is not surfaced in Swift,
            // so decide from the matched text whether a clock time was given.
            let matched = (searchable as NSString).substring(with: match.range)
            let carriesTime = extractTime(from: matched, excluding: nil) != nil

            // NSDataDetector answers with an instant resolved in the *system's*
            // time zone, ignoring the calendar this parser was handed — and for
            // a dateless match it picks noon, not midnight. Taken literally that
            // instant can land on the day either side of the one the user named
            // once the two zones differ. Re-read the day (and any clock time) it
            // named in its own zone, then rebuild it in ours.
            var namingZone = Calendar(identifier: .gregorian)
            namingZone.timeZone = match.timeZone ?? .current
            let named = namingZone.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )

            var rebuilt = DateComponents()
            rebuilt.year = named.year
            rebuilt.month = named.month
            rebuilt.day = named.day
            if carriesTime {
                rebuilt.hour = named.hour
                rebuilt.minute = named.minute
            }
            // Undated matches start the day, matching every other branch here —
            // the writer substitutes the user's default time when hasTime is false.
            guard let resolved = calendar.date(from: rebuilt) else { return nil }

            return DateHit(
                date: resolved,
                hasTime: carriesTime,
                sourceText: original.substring(with: match.range),
                ranges: [match.range]
            )
        }

        return nil
    }

    /// Pairs a resolved day with whatever clock time appears elsewhere in the string.
    private static func combine(
        dayStart: Date,
        dayRange: NSRange,
        daySource: String,
        impliedTime: TimeOfDay?,
        searchable: String,
        original: NSString,
        now: Date,
        calendar: Calendar
    ) -> DateHit {
        if let time = extractTime(from: searchable, excluding: dayRange) {
            return DateHit(
                date: apply(time: time.value, to: dayStart, now: now, calendar: calendar),
                hasTime: true,
                sourceText: "\(daySource) \(original.substring(with: time.range))",
                ranges: [dayRange, time.range]
            )
        }
        if let implied = impliedTime {
            return DateHit(
                date: apply(time: implied, to: dayStart, now: now, calendar: calendar),
                hasTime: true,
                sourceText: daySource,
                ranges: [dayRange]
            )
        }
        return DateHit(date: dayStart, hasTime: false, sourceText: daySource, ranges: [dayRange])
    }

    private static func extractTime(
        from searchable: String,
        excluding: NSRange?
    ) -> (value: TimeOfDay, range: NSRange)? {
        let ns = searchable as NSString
        for pattern in timeRegexes {
            for match in pattern.matches(in: searchable, range: ns.fullRange) {
                if let excluding, NSIntersectionRange(match.range, excluding).length > 0 { continue }
                if let time = timeOfDay(from: match, in: ns) {
                    return (time, match.range)
                }
            }
        }
        return nil
    }

    private static func timeOfDay(from match: NSTextCheckingResult, in ns: NSString) -> TimeOfDay? {
        func group(_ index: Int) -> String? {
            guard index < match.numberOfRanges, match.range(at: index).location != NSNotFound else { return nil }
            return ns.substring(with: match.range(at: index))
        }

        // noon / midday / midnight
        if let word = group(1)?.lowercased(), ["noon", "midday", "midnight"].contains(word) {
            return TimeOfDay(hour: word == "midnight" ? 0 : 12, minute: 0, isAmbiguous: false)
        }

        guard let first = group(1), var hour = Int(first) else { return nil }
        var minute = 0
        var meridiem: String?

        if let second = group(2) {
            if let m = Int(second) { minute = m } else { meridiem = second.lowercased() }
        }
        if let third = group(3) { meridiem = third.lowercased() }

        guard minute < 60 else { return nil }

        if let meridiem {
            let isPM = meridiem.hasPrefix("p")
            guard (1...12).contains(hour) else { return nil }
            if isPM, hour != 12 { hour += 12 }
            if !isPM, hour == 12 { hour = 0 }
            return TimeOfDay(hour: hour, minute: minute, isAmbiguous: false)
        }

        // No meridiem. A minute component implies 24h ("17:00"); a bare "at 5" does not.
        let hadMinutes = group(2).flatMap(Int.init) != nil
        guard hour < 24 else { return nil }
        return TimeOfDay(hour: hour, minute: minute, isAmbiguous: !hadMinutes && hour <= 12)
    }

    private static func apply(time: TimeOfDay, to dayStart: Date, now: Date, calendar: Calendar) -> Date {
        func build(_ hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: time.minute, second: 0, of: dayStart) ?? dayStart
        }
        guard time.isAmbiguous else { return build(time.hour) }
        // "at 5" — prefer the reading that is still ahead of us.
        let candidates = [time.hour, time.hour + 12].filter { $0 < 24 }
        return candidates.first(where: { build($0) > now }).map(build) ?? build(candidates[0])
    }

    private struct OffsetHit {
        var date: Date
        var carriesTime: Bool
    }

    private static func resolveOffset(amount: Int, unit: String, now: Date, calendar: Calendar) -> OffsetHit? {
        switch unit {
        case "minute", "minutes", "min", "mins":
            return calendar.date(byAdding: .minute, value: amount, to: now).map { OffsetHit(date: $0, carriesTime: true) }
        case "hour", "hours", "hr", "hrs":
            return calendar.date(byAdding: .hour, value: amount, to: now).map { OffsetHit(date: $0, carriesTime: true) }
        case "day", "days":
            return calendar.date(byAdding: .day, value: amount, to: now).map { OffsetHit(date: $0, carriesTime: false) }
        case "week", "weeks":
            return calendar.date(byAdding: .day, value: amount * 7, to: now).map { OffsetHit(date: $0, carriesTime: false) }
        case "month", "months":
            return calendar.date(byAdding: .month, value: amount, to: now).map { OffsetHit(date: $0, carriesTime: false) }
        default:
            return nil
        }
    }

    private static func weekdayNumber(for name: String) -> Int? {
        // Calendar convention: Sunday == 1.
        switch name.prefix(3) {
        case "sun": 1
        case "mon": 2
        case "tue": 3
        case "wed": 4
        case "thu": 5
        case "fri": 6
        case "sat": 7
        default: nil
        }
    }

    // MARK: - Title cleanup

    /// Blanks out already-claimed ranges so later passes cannot match inside them,
    /// while keeping every index aligned with the original string.
    private static func maskedString(_ text: NSString, excluding ranges: [NSRange]) -> String {
        guard !ranges.isEmpty else { return text as String }
        let mutable = NSMutableString(string: text)
        for range in ranges {
            mutable.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        return mutable as String
    }

    private static func cleanedTitle(from text: NSString, removing ranges: [NSRange]) -> String {
        let mutable = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            mutable.replaceCharacters(in: range, with: "")
        }
        var title = mutable as String
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // "call dentist on" -> "call dentist"
        title = danglingPrepositionRegex.stringByReplacingMatches(
            in: title, range: (title as NSString).fullRange, withTemplate: ""
        )
        title = leadingPrepositionRegex.stringByReplacingMatches(
            in: title, range: (title as NSString).fullRange, withTemplate: ""
        )
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension NSString {
    var fullRange: NSRange { NSRange(location: 0, length: length) }
}
