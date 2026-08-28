import AppKit
import SwiftUI

/// A curated SF Symbol picker.
///
/// Not a full symbol browser: the system ships thousands, and a grid of the
/// couple of hundred that actually read as a task category at 15pt is more
/// useful than a search over all of them. The field still accepts any name, so
/// nothing is out of reach.
struct SymbolPickerView: View {
    @Binding var symbolName: String
    let tint: Color

    @State private var query = ""

    private var results: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return Self.symbols }
        let matches = Self.symbols.filter { $0.contains(trimmed) }
        // A name typed in full counts even when it is not on the curated list,
        // so nothing in SF Symbols is out of reach.
        if matches.isEmpty, NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil {
            return [trimmed]
        }
        return matches
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search symbols", text: $query)
                .textFieldStyle(.roundedBorder)
                // Or Form lifts the placeholder out as a row label.
                .labelsHidden()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 5)], spacing: 5) {
                    ForEach(results, id: \.self) { name in
                        Button {
                            symbolName = name
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 15))
                                .frame(width: 34, height: 28)
                                .foregroundStyle(name == symbolName ? Color.white : tint)
                                .background(
                                    name == symbolName ? tint : Color.secondary.opacity(0.1),
                                    in: .rect(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 108)

            if results.isEmpty {
                Text("No symbol called that.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Grouped roughly by what a filter tends to be about: time, work, places,
    /// people, and status.
    static let symbols: [String] = [
        "sun.max.fill", "sunrise.fill", "sunset.fill", "moon.fill", "moon.stars.fill",
        "calendar", "calendar.badge.clock", "calendar.badge.exclamationmark", "clock",
        "clock.badge.checkmark", "alarm", "timer", "hourglass", "deskclock",
        "tray", "tray.full", "tray.2", "archivebox", "shippingbox", "internaldrive",
        "checklist", "checkmark.circle", "checkmark.seal", "list.bullet", "list.number",
        "list.bullet.clipboard", "line.3.horizontal.decrease.circle", "flag", "flag.fill",
        "bookmark.fill", "star.fill", "sparkles", "bolt.fill", "flame.fill",
        "exclamationmark.triangle.fill", "exclamationmark.circle.fill",
        "briefcase.fill", "case.fill", "building.2.fill", "building.columns.fill",
        "desktopcomputer", "laptopcomputer", "keyboard", "printer.fill", "display",
        "person.fill", "person.2.fill", "person.3.fill", "person.crop.circle",
        "figure.walk", "figure.run", "figure.strengthtraining.traditional",
        "house.fill", "bed.double.fill", "sofa.fill", "shower.fill", "washer.fill",
        "cart.fill", "creditcard.fill", "banknote.fill", "dollarsign.circle.fill",
        "envelope.fill", "paperplane.fill", "phone.fill", "bubble.left.fill",
        "video.fill", "mic.fill", "headphones", "music.note",
        "doc.fill", "doc.text.fill", "folder.fill", "paperclip", "pencil", "highlighter",
        "book.fill", "books.vertical.fill", "graduationcap.fill", "newspaper.fill",
        "car.fill", "airplane", "tram.fill", "bicycle", "fuelpump.fill",
        "map.fill", "mappin.and.ellipse", "globe", "location.fill",
        "heart.fill", "cross.case.fill", "pills.fill", "stethoscope", "leaf.fill",
        "cup.and.saucer.fill", "fork.knife", "carrot.fill", "birthday.cake.fill",
        "gift.fill", "party.popper.fill", "gamecontroller.fill", "camera.fill",
        "paintbrush.fill", "hammer.fill", "wrench.and.screwdriver.fill", "gearshape.fill",
        "trash.fill", "arrow.triangle.2.circlepath", "repeat", "infinity",
        "target", "scope", "chart.bar.fill", "chart.line.uptrend.xyaxis",
        "lightbulb.fill", "brain.head.profile", "eye.fill", "hand.raised.fill",
    ]
}

/// The tint well, shown as a row of swatches rather than a colour picker so the
/// value always round-trips through `FilterTint`.
struct TintPickerView: View {
    @Binding var tint: FilterTint

    private let columns = [GridItem(.adaptive(minimum: 26), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(FilterTint.allCases) { option in
                Button { tint = option } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 20, height: 20)
                        .overlay {
                            if option == tint {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay {
                            Circle().strokeBorder(.primary.opacity(option == tint ? 0.35 : 0.12))
                        }
                }
                .buttonStyle(.plain)
                .help(option.label)
            }
        }
    }
}
