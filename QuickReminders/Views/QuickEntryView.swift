import AppKit
import SwiftUI

struct QuickEntryView: View {
    let service: RemindersService
    let preferences: Preferences
    var initialText: String = ""
    var dismiss: () -> Void
    /// Tells the panel to ignore automatic dismissal while pinned.
    var setPinned: (Bool) -> Void = { _ in }

    @State private var rawInput = ""
    @State private var parsed = ParseResult.empty
    @State private var notes = ""
    @State private var selectedListID: String?

    /// Manual overrides win over whatever the parser found. `dayCleared` and
    /// `timeCleared` distinguish "not set" from "deliberately removed".
    @State private var manualDay: Date?
    @State private var manualTime: TimeOfDay?
    @State private var manualPriority: ReminderPriority?
    @State private var dayCleared = false
    @State private var timeCleared = false
    @State private var datePickerShown = false
    @State private var isPinned = false
    @State private var timePickerShown = false
    @State private var errorText: String?

    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, notes }

    private static let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    /// How far a stepper travels out from under the clock — the clock's own width,
    /// so each one starts exactly covered by it.
    private static let stepperTravel: CGFloat = 26

    /// Shared by every chip and toolbar change so the panel moves as one thing.
    private static let settle = Animation.snappy(duration: 0.24, extraBounce: 0.05)

    /// Gives a bare glyph a real click target.
    ///
    /// Without this the hit area is only the glyph's own bounds — a few points
    /// across — which is well under what a pointer can comfortably hit.
    ///
    /// Two hover treatments: `.filled` draws a circular field behind the glyph,
    /// `.dim` leaves the glyph sitting faded until the pointer brings it up.
    private struct HitArea: ViewModifier {
        enum Hover { case filled, dim }

        var diameter: CGFloat = 26
        var hover: Hover = .filled
        @State private var hovering = false

        private var fadedOpacity: Double {
            hover == .dim && !hovering ? 0.45 : 1
        }

        func body(content: Content) -> some View {
            content
                .opacity(fadedOpacity)
                .frame(width: diameter, height: diameter)
                // The whole circle is clickable, not just the drawn pixels.
                .contentShape(Circle())
                .background {
                    Circle()
                        .fill(.quaternary)
                        .opacity(hover == .filled && hovering ? 1 : 0)
                }
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }

    // MARK: - Derived state

    private var parsedDay: Date? {
        parsed.dueDate.map { Calendar.current.startOfDay(for: $0) }
    }

    private var parsedTime: TimeOfDay? {
        guard parsed.hasTime, let due = parsed.dueDate else { return nil }
        return TimeOfDay(from: due)
    }

    private var effectiveDay: Date? {
        if let manualDay { return manualDay }
        if dayCleared { return nil }
        if let parsedDay { return parsedDay }
        // A time on its own means today.
        return effectiveTimeRaw != nil ? Calendar.current.startOfDay(for: Date()) : nil
    }

    /// The time before the "a time implies a day" rule is applied.
    private var effectiveTimeRaw: TimeOfDay? {
        if let manualTime { return manualTime }
        if timeCleared { return nil }
        return parsedTime
    }

    private var effectiveTime: TimeOfDay? {
        effectiveDay == nil ? nil : effectiveTimeRaw
    }

    private var effectivePriority: ReminderPriority {
        manualPriority ?? parsed.priority
    }

    private var draft: ReminderDraft {
        let day = effectiveDay
        return ReminderDraft(
            title: parsed.cleanedTitle,
            notes: notes,
            listID: selectedListID,
            dueDate: day.map { effectiveTime?.applied(to: $0) ?? $0 },
            hasTime: effectiveTime != nil,
            priority: effectivePriority
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            fields
            chips
            footer
        }
        .frame(width: 560)
        .clipShape(Self.cardShape)
        // Liquid Glass draws its own edge highlight and shadowing, so the hand
        // drawn hairline border that the flat material needed is gone.
        .glassEffect(.regular, in: Self.cardShape)
        .defaultFocus($focus, .title)
        .task { await prepare() }
        .task(id: rawInput) {
            // Debounce so chips settle rather than flickering on every keystroke.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            parsed = ReminderParser.parse(rawInput, detectDates: !dayCleared)
        }
        .background { priorityShortcuts }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ListPickerView(lists: service.lists, selection: $selectedListID)
            Spacer(minLength: 0)
            pinButton
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .modifier(HitArea())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        // The header doubles as the title bar. A plain `.gesture` leaves the
        // list menu and close button their own clicks.
        .gesture(WindowDragGesture())
    }

    private var pinButton: some View {
        Button {
            isPinned.toggle()
            setPinned(isPinned)
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.body.weight(.semibold))
                .foregroundStyle(isPinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .modifier(HitArea())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isPinned)
        .help(isPinned
              ? "Unpin — the panel closes again when you switch away"
              : "Pin — keep the panel open while you look something up")
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if rawInput.isEmpty {
                    Text("New Reminder")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                TextField("", text: $rawInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title)
                    .lineLimit(1...4)
                    .focused($focus, equals: .title)
                    .onKeyPress(.return, phases: .down) { press in
                        guard preferences.submitShortcut == .returnKey,
                              !press.modifiers.contains(.shift)
                        else { return .ignored }
                        save()
                        return .handled
                    }
            }

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Notes")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                TextField("", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    // Exactly two lines, always: `reservesSpace` holds them open
                    // when empty, and the hard limit means a longer note scrolls
                    // inside the field instead of growing the window.
                    .lineLimit(2, reservesSpace: true)
                    .focused($focus, equals: .notes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    // MARK: - Chips

    private var hasChips: Bool {
        effectiveDay != nil || effectiveTime != nil || effectivePriority != .none
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                // A hidden chip holds the lane open, so the panel keeps its height
                // whether or not anything is parsed and never jumps as you type.
                // Measured from a real chip rather than a magic number, so it stays
                // correct if the font or accessibility text size changes.
                ParsedChipsView(
                    day: Date(), time: nil, priority: .none,
                    onRemoveDay: {}, onRemoveTime: {}, onRemovePriority: {}
                )
                .hidden()

                if hasChips {
                    ParsedChipsView(
                        day: effectiveDay,
                        time: effectiveTime,
                        priority: effectivePriority,
                        onRemoveDay: clearDay,
                        onRemoveTime: clearTime,
                        onRemovePriority: { manualPriority = ReminderPriority.none }
                    )
                }
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .animation(Self.settle, value: effectiveDay)
        .animation(Self.settle, value: effectiveTime)
        .animation(Self.settle, value: effectivePriority)
        .animation(Self.settle, value: errorText)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                dateControl
                timeControl
                priorityButton
                Spacer(minLength: 0)
                addButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .animation(Self.settle, value: effectiveTime == nil)
            .animation(Self.settle, value: effectiveDay == nil)
            .animation(Self.settle, value: effectivePriority)
            .animation(.easeInOut(duration: 0.15), value: draft.isSubmittable)
        }
    }

    private var dateControl: some View {
        Button {
            datePickerShown.toggle()
        } label: {
            Image(systemName: "calendar")
                .font(.body.weight(.semibold))
                .foregroundStyle(effectiveDay == nil ? Color.secondary : Color.blue)
                .modifier(HitArea())
        }
        .buttonStyle(.plain)
        .help("Due date")
        .popover(isPresented: $datePickerShown, arrowEdge: .bottom) {
            DatePopoverView(
                selection: chosenDate,
                hasDate: effectiveDay != nil,
                onClear: {
                    clearDay()
                    datePickerShown = false
                },
                onClose: { datePickerShown = false }
            )
        }
    }

    /// Backs the calendar; reading falls back to today so it opens on the
    /// current month rather than 1 January 2001.
    private var chosenDate: Binding<Date> {
        Binding(
            get: { effectiveDay ?? Calendar.current.startOfDay(for: Date()) },
            set: { newValue in
                manualDay = Calendar.current.startOfDay(for: newValue)
                dayCleared = false
            }
        )
    }

    /// The clock is always the same view; the steppers slide out from behind it
    /// once a time exists. Swapping the whole control out instead would replace
    /// the clock too, and it would cross-fade rather than stay put.
    private var timeControl: some View {
        HStack(spacing: 2) {
            if effectiveTime != nil {
                stepButton(symbol: "minus.circle.fill", minutes: -1)
                    .transition(.offset(x: Self.stepperTravel))
                    .zIndex(0)
            }
            clockMenu
                // Drawn above the steppers so they are hidden underneath it at
                // the start of the slide, and emerge from behind it.
                .zIndex(1)
            if effectiveTime != nil {
                stepButton(symbol: "plus.circle.fill", minutes: 1)
                    .transition(.offset(x: -Self.stepperTravel))
                    .zIndex(0)
            }
        }
        .padding(.horizontal, 3)
        .background {
            Capsule()
                .fill(.quaternary.opacity(0.5))
                .opacity(effectiveTime == nil ? 0 : 1)
        }
    }

    private var clockMenu: some View {
        Button {
            timePickerShown.toggle()
        } label: {
            Image(systemName: "clock")
                .font(.body.weight(.semibold))
                .foregroundStyle(effectiveTime == nil ? Color.secondary : Color.red)
                .modifier(HitArea())
        }
        .buttonStyle(.plain)
        .help("Time")
        .popover(isPresented: $timePickerShown, arrowEdge: .bottom) {
            TimePopoverView(
                selection: pickedTime,
                onClear: {
                    clearTime()
                    timePickerShown = false
                },
                onClose: { timePickerShown = false }
            )
        }
    }

    /// Writing a time also pins the day, since a time on its own means today.
    private var pickedTime: Binding<TimeOfDay?> {
        Binding(
            get: { effectiveTime },
            set: { newValue in
                if let newValue {
                    setTime(newValue)
                } else {
                    clearTime()
                }
            }
        )
    }

    private func stepButton(symbol: String, minutes: Int) -> some View {
        Button {
            // Shift steps by half an hour instead of a full one.
            let shift = NSEvent.modifierFlags.contains(.shift)
            step(byMinutes: minutes * (shift ? 30 : 60))
        } label: {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .modifier(HitArea(diameter: 24, hover: .dim))
        }
        .buttonStyle(.plain)
        .help(minutes < 0 ? "Earlier by an hour (⇧ for 30 min)" : "Later by an hour (⇧ for 30 min)")
    }

    private var priorityButton: some View {
        Button {
            manualPriority = effectivePriority.cyclingNext
        } label: {
            ZStack {
                // Reserves the widest state so the toolbar does not shift
                // sideways as the number of marks changes.
                Text(ReminderPriority.high.bangs).hidden()
                PriorityMarksView(priority: effectivePriority, showsPlaceholder: true)
                    .foregroundStyle(effectivePriority == .none ? Color.secondary : Color.orange)
            }
            .font(.body.weight(.semibold))
            .modifier(HitArea())
        }
        .buttonStyle(.plain)
        .help("Priority — click to cycle through ! !! !!! (⌘1 ⌘2 ⌘3)")
    }

    private var addButton: some View {
        Button(action: save) {
            HStack(spacing: 7) {
                Text("Add Reminder")
                // Supporting info, not a second label: a size down and well back
                // in contrast, so it reads as a hint attached to the action.
                Text(preferences.submitShortcut.hint)
                    .font(.caption)
                    .opacity(0.55)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!draft.isSubmittable)
        .keyboardShortcut(.return, modifiers: .command)
    }

    /// Zero-sized buttons that exist purely to own keyboard shortcuts.
    private var priorityShortcuts: some View {
        VStack {
            Button("") { manualPriority = .high }.keyboardShortcut("1", modifiers: .command)
            Button("") { manualPriority = .medium }.keyboardShortcut("2", modifiers: .command)
            Button("") { manualPriority = .low }.keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    // MARK: - Actions

    private func prepare() async {
        // Text and focus first: requesting access can block on a system prompt,
        // and the field must be typable the moment the panel appears.
        if rawInput.isEmpty, !initialText.isEmpty { rawInput = initialText }
        focus = .title
        service.defaultTime = preferences.defaultTime

        // Re-assert once the panel is actually key; a focus set during the
        // window's own ordering-front can be discarded.
        Task {
            try? await Task.sleep(for: .milliseconds(40))
            focus = .title
        }

        if service.access == .undetermined {
            await service.requestAccess()
        } else if service.access == .granted {
            service.loadLists()
        }

        selectedListID = preferences.preferredListID(fallback: service.defaultListID)
        errorText = service.access == .denied ? RemindersError.noAccess.errorDescription : nil
    }

    private func setDay(dayOffset: Int = 0, monthOffset: Int = 0) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shifted = calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
        manualDay = calendar.date(byAdding: .day, value: dayOffset, to: shifted)
        dayCleared = false
    }

    private func setTime(_ time: TimeOfDay) {
        manualTime = time
        timeCleared = false
        if effectiveDay == nil { setDay(dayOffset: 0) }
    }

    private func step(byMinutes delta: Int) {
        guard let current = effectiveTime else { return }
        manualTime = current.stepped(byMinutes: delta)
        timeCleared = false
    }

    private func clearDay() {
        manualDay = nil
        dayCleared = true
        // A time cannot outlive its date.
        manualTime = nil
        timeCleared = true
        // Re-parse with dates off so the words go back into the title.
        parsed = ReminderParser.parse(rawInput, detectDates: false)
    }

    private func clearTime() {
        manualTime = nil
        timeCleared = true
    }

    private func save() {
        guard draft.isSubmittable else { return }
        do {
            service.defaultTime = preferences.defaultTime
            try service.save(draft)
            preferences.lastUsedListID = selectedListID
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
