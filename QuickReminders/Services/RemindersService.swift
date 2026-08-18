import EventKit
import Foundation
import Observation

/// EventKit-backed reminder storage.
///
/// Scope note: EventKit exposes title, notes, URL, priority, list, due date and
/// alarms — and nothing else. Tags, the flag and attachments are not writable
/// here at all; see `ReminderWriter` for where they would go.
@MainActor
@Observable
final class RemindersService: ReminderWriter {

    enum Access: Equatable {
        case undetermined
        case granted
        case denied
    }

    private(set) var access: Access = .undetermined
    private(set) var lists: [ReminderList] = []
    private(set) var defaultListID: String?

    /// Hour/minute used when the user gave a day but no clock time.
    var defaultTime: (hour: Int, minute: Int) = (9, 0)

    private let store = EKEventStore()
    /// Preview services hold canned lists that must not be replaced by a real
    /// (and, with no access, empty) EventKit fetch.
    private var isPreview = false

    init() {
        refreshAccessStatus()
    }

    /// Builds a service with canned data, for snapshots and SwiftUI previews.
    static func preview(lists: [ReminderList]) -> RemindersService {
        let service = RemindersService()
        service.isPreview = true
        service.access = .granted
        service.lists = lists
        service.defaultListID = lists.first?.id
        return service
    }

    // MARK: - Authorization

    func refreshAccessStatus() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            access = .granted
        case .denied, .restricted, .writeOnly:
            access = .denied
        case .notDetermined:
            access = .undetermined
        @unknown default:
            access = .undetermined
        }
    }

    /// macOS 14+ API. The older `requestAccess(to:)` is deprecated and does not
    /// grant the full access reading the user's lists requires.
    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToReminders()
            access = granted ? .granted : .denied
        } catch {
            NSLog("Quick Reminders: reminders access request failed — \(error.localizedDescription)")
            access = .denied
        }
        if access == .granted { loadLists() }
    }

    // MARK: - Lists

    func loadLists() {
        guard access == .granted, !isPreview else { return }
        let calendars = store.calendars(for: .reminder)
        lists = calendars
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title, color: ListColor(cgColor: $0.cgColor)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        defaultListID = store.defaultCalendarForNewReminders()?.calendarIdentifier ?? lists.first?.id
    }

    // MARK: - Saving

    func save(_ draft: ReminderDraft) throws {
        guard access == .granted else { throw RemindersError.noAccess }

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw RemindersError.emptyTitle }

        guard let calendar = resolveCalendar(draft.listID) else { throw RemindersError.noList }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        reminder.priority = draft.priority.rawValue

        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { reminder.notes = notes }

        if let due = draft.dueDate {
            let fireDate = draft.hasTime ? due : applyingDefaultTime(to: due)
            let cal = Calendar.current

            // Two things matter here, and both are easy to get wrong:
            //  1. The components must carry a calendar and time zone, or the
            //     reminder can land undated.
            //  2. A due date alone never notifies — the alarm is what fires.
            var components = cal.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: fireDate
            )
            components.calendar = cal
            components.timeZone = TimeZone.current
            reminder.dueDateComponents = components
            reminder.addAlarm(EKAlarm(absoluteDate: fireDate))
        }

        try store.save(reminder, commit: true)
    }

    // MARK: - Helpers

    private func resolveCalendar(_ listID: String?) -> EKCalendar? {
        if let listID, let match = store.calendar(withIdentifier: listID), match.allowsContentModifications {
            return match
        }
        if let fallback = store.defaultCalendarForNewReminders() { return fallback }
        return store.calendars(for: .reminder).first { $0.allowsContentModifications }
    }

    private func applyingDefaultTime(to date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(
            bySettingHour: defaultTime.hour, minute: defaultTime.minute, second: 0, of: date
        ) ?? date
    }
}
