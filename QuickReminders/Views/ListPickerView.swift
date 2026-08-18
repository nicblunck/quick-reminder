import SwiftUI

/// The destination list, shown as a menu in the panel header.
///
/// EventKit exposes a list's name and colour but *not* its icon, so the glyph is
/// a generic one tinted with the real list colour rather than the symbol shown
/// in Reminders.app.
struct ListPickerView: View {
    let lists: [ReminderList]
    @Binding var selection: String?

    private var current: ReminderList? {
        lists.first { $0.id == selection } ?? lists.first
    }

    private var tint: Color {
        current?.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .secondary
    }

    var body: some View {
        Menu {
            ForEach(lists) { list in
                Button {
                    selection = list.id
                } label: {
                    if list.id == current?.id {
                        Label(list.title, systemImage: "checkmark")
                    } else {
                        Text(list.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                Text(current?.title ?? "No lists")
                    .font(.headline)
                    .foregroundStyle(tint)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint.opacity(0.7))
            }
        }
        // Not `.borderlessButton`: that style discards leading label content (the
        // icon) and draws its own indicator ahead of the title.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(lists.isEmpty)
    }
}
