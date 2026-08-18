import Foundation
import Testing

/// All tests run against a frozen reference date in a fixed calendar and time
/// zone, so nothing here depends on when or where it runs.
private let zone = TimeZone(identifier: "America/Los_Angeles")!

private let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = zone
    cal.locale = Locale(identifier: "en_US")
    return cal
}()

/// Monday 15 June 2026, 10:00.
private let now: Date = {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 15
    comps.hour = 10; comps.minute = 0
    comps.timeZone = zone
    return calendar.date(from: comps)!
}()

private func parse(_ input: String) -> ParseResult {
    ReminderParser.parse(input, now: now, calendar: calendar)
}

private func components(_ date: Date) -> DateComponents {
    calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
}

@Suite("Reference date sanity")
struct ReferenceDateTests {
    @Test("The frozen reference date really is Monday 15 June 2026")
    func referenceDate() throws {
        let c = components(now)
        #expect(c.year == 2026)
        #expect(c.month == 6)
        #expect(c.day == 15)
        #expect(c.weekday == 2) // Monday
    }
}

@Suite("Plain titles")
struct PlainTitleTests {
    @Test("A bare title is left completely alone")
    func bareTitle() throws {
        let result = parse("buy milk")
        #expect(result.cleanedTitle == "buy milk")
        #expect(result.dueDate == nil)
        #expect(result.hasTime == false)
        #expect(result.priority == .none)
    }

    @Test("Hashtags survive in the title, since EventKit cannot write real tags")
    func hashtagsSurvive() throws {
        let result = parse("renew passport #admin #travel")
        #expect(result.cleanedTitle == "renew passport #admin #travel")
    }

    @Test("Empty input yields an empty, unsubmittable draft")
    func emptyInput() throws {
        let result = parse("   ")
        #expect(result.cleanedTitle.isEmpty)
        #expect(result.dueDate == nil)
    }
}

@Suite("Priority")
struct PriorityTests {
    @Test("Bang counts map to low, medium and high", arguments: [
        ("a !", ReminderPriority.low),
        ("a !!", ReminderPriority.medium),
        ("a !!!", ReminderPriority.high),
    ])
    func bangs(input: String, expected: ReminderPriority) throws {
        let result = parse(input)
        #expect(result.priority == expected)
        #expect(result.cleanedTitle == "a")
    }

    @Test("A bang glued to a word is punctuation, not a priority")
    func attachedBangIsNotPriority() throws {
        let result = parse("ship it!")
        #expect(result.priority == .none)
        #expect(result.cleanedTitle == "ship it!")
    }
}

@Suite("Relative days")
struct RelativeDayTests {
    @Test("tomorrow with a time resolves to the next day at that hour")
    func tomorrowAtFive() throws {
        let result = parse("call dentist tomorrow 5pm")
        let c = try components(#require(result.dueDate))
        #expect(result.cleanedTitle == "call dentist")
        #expect(c.day == 16)
        #expect(c.hour == 17)
        #expect(c.minute == 0)
        #expect(result.hasTime == true)
    }

    @Test("A day with no time reports hasTime false so the default time applies")
    func dayWithoutTime() throws {
        let result = parse("water plants tomorrow")
        let c = try components(#require(result.dueDate))
        #expect(result.cleanedTitle == "water plants")
        #expect(c.day == 16)
        #expect(result.hasTime == false)
    }

    @Test("tonight implies 8pm today")
    func tonight() throws {
        let result = parse("take out bins tonight")
        let c = try components(#require(result.dueDate))
        #expect(c.day == 15)
        #expect(c.hour == 20)
        #expect(result.hasTime == true)
    }

    @Test("eod implies 5pm today")
    func endOfDay() throws {
        let result = parse("send invoice eod")
        let c = try components(#require(result.dueDate))
        #expect(c.day == 15)
        #expect(c.hour == 17)
        #expect(result.hasTime == true)
    }

    @Test("tmrw is understood as tomorrow")
    func shorthandTomorrow() throws {
        let result = parse("standup tmrw")
        let c = try components(#require(result.dueDate))
        #expect(c.day == 16)
        #expect(result.cleanedTitle == "standup")
    }
}

@Suite("Weekdays")
struct WeekdayTests {
    @Test("A bare weekday lands on the coming occurrence")
    func comingFriday() throws {
        let result = parse("gym friday")
        let c = try components(#require(result.dueDate))
        #expect(c.weekday == 6) // Friday
        #expect(c.day == 19)    // the Friday of the reference week
        #expect(result.cleanedTitle == "gym")
    }

    @Test("next + weekday skips a further week")
    func nextFriday() throws {
        let result = parse("gym next friday")
        let c = try components(#require(result.dueDate))
        #expect(c.weekday == 6)
        #expect(c.day == 26)
    }

    @Test("Naming today's weekday means today, not a week out")
    func todaysWeekday() throws {
        let result = parse("review monday")
        let c = try components(#require(result.dueDate))
        #expect(c.day == 15)
    }
}

@Suite("Times")
struct TimeTests {
    @Test("A bare future time today stays today")
    func bareTimeToday() throws {
        let result = parse("coffee 3pm")
        let c = try components(#require(result.dueDate))
        #expect(c.day == 15)
        #expect(c.hour == 15)
        #expect(result.hasTime == true)
    }

    @Test("A bare time already past rolls to tomorrow")
    func bareTimeRollsOver() throws {
        let result = parse("coffee 8am")
        let c = try components(#require(result.dueDate))
        #expect(c.day == 16)
        #expect(c.hour == 8)
    }

    @Test("24-hour times are read literally")
    func twentyFourHour() throws {
        let result = parse("deploy 17:30")
        let c = try components(#require(result.dueDate))
        #expect(c.hour == 17)
        #expect(c.minute == 30)
    }

    @Test("noon and midnight are understood")
    func namedTimes() throws {
        let noon = try #require(parse("lunch noon").dueDate)
        let midnight = try #require(parse("backup midnight").dueDate)
        #expect(components(noon).hour == 12)
        #expect(components(midnight).hour == 0)
    }

    @Test("An ambiguous 'at 5' picks the reading still ahead of now")
    func ambiguousHour() throws {
        let result = parse("standup at 5")
        let c = try components(#require(result.dueDate))
        #expect(c.hour == 17) // 05:00 already passed at 10:00
        #expect(result.cleanedTitle == "standup")
    }
}

@Suite("Relative offsets")
struct OffsetTests {
    @Test("in 30 minutes resolves to an exact instant")
    func inMinutes() throws {
        let result = parse("stretch in 30 minutes")
        let c = try components(#require(result.dueDate))
        #expect(c.hour == 10)
        #expect(c.minute == 30)
        #expect(result.hasTime == true)
        #expect(result.cleanedTitle == "stretch")
    }

    @Test("in 3 days is a day offset, so it carries no time of its own")
    func inDays() throws {
        let result = parse("follow up in 3 days")
        let c = try components(#require(result.dueDate))
        #expect(c.day == 18)
        #expect(result.hasTime == false)
    }

    @Test("A day offset still accepts an explicit time")
    func offsetWithTime() throws {
        let result = parse("follow up in 3 days at 2pm")
        let c = try components(#require(result.dueDate))
        #expect(c.day == 18)
        #expect(c.hour == 14)
        #expect(result.hasTime == true)
    }
}

@Suite("Absolute dates")
struct AbsoluteDateTests {
    @Test("An absolute month/day falls through to NSDataDetector")
    func absoluteDate() throws {
        let result = parse("book flights August 20")
        let c = try components(#require(result.dueDate))
        #expect(c.month == 8)
        #expect(c.day == 20)
        #expect(result.cleanedTitle == "book flights")
    }
}

@Suite("Title cleanup")
struct TitleCleanupTests {
    @Test("Everything combines and the title comes out clean")
    func combined() throws {
        let result = parse("call dentist tomorrow 5pm !!")
        let c = try components(#require(result.dueDate))
        #expect(result.cleanedTitle == "call dentist")
        #expect(c.day == 16)
        #expect(c.hour == 17)
        #expect(result.priority == .medium)
    }

    @Test("A preposition left dangling by a removed token is trimmed")
    func danglingPreposition() throws {
        #expect(parse("submit report on friday").cleanedTitle == "submit report")
        #expect(parse("standup at 9am").cleanedTitle == "standup")
    }

    @Test("Date detection can be switched off so the words stay in the title")
    func datesDisabled() throws {
        let result = ReminderParser.parse(
            "review tomorrow's agenda", now: now, calendar: calendar, detectDates: false
        )
        #expect(result.dueDate == nil)
        #expect(result.cleanedTitle == "review tomorrow's agenda")
    }
}
