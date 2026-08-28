import KeyboardShortcuts
import SwiftUI

/// A plain settings form, self-sizing, no sidebar.
///
/// Filters live in their own window rather than a pane here: they need far more
/// room than a settings form, and an AppKit app cannot produce a convincing
/// System Settings sidebar anyway — it has no SwiftUI `App` to hang the built-in
/// `Settings` scene off.
struct SettingsView: View {
    let service: RemindersService
    let preferences: Preferences
    let updater: UpdaterService
    let openFilters: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    /// `nil` means "whichever list was used last"; anything else pins a list.
    /// One control rather than a mode picker that reveals a second picker.
    private var destination: Binding<String?> {
        Binding(
            get: { preferences.listMode == .lastUsed ? nil : preferences.fixedListID },
            set: { newValue in
                if let newValue {
                    preferences.fixedListID = newValue
                    preferences.listMode = .fixed
                } else {
                    preferences.listMode = .lastUsed
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Open quick entry:", name: .toggleQuickEntry)
                Button("Reset to ⌥Space") { HotkeyManager.resetToDefault() }
            }

            Section("Defaults") {
                Picker("Save to:", selection: destination) {
                    Text("Last used list").tag(String?.none)
                    if !service.lists.isEmpty {
                        Divider()
                        ForEach(service.lists) { list in
                            Text(list.title).tag(Optional(list.id))
                        }
                    }
                }

                Picker("Add reminder with:", selection: Binding(
                    get: { preferences.submitShortcut },
                    set: { preferences.submitShortcut = $0 }
                )) {
                    ForEach(Preferences.SubmitShortcut.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                DatePicker(
                    "Reminders without a time:",
                    selection: Binding(
                        get: { preferences.defaultTimeAsDate },
                        set: { preferences.defaultTimeAsDate = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }

            Section("Widgets") {
                LabeledContent("Filters") {
                    Button("Edit Filters…", action: openFilters)
                }
            }

            Section("Updates") {
                Toggle("Check automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                LabeledContent("Last checked") {
                    HStack(spacing: 10) {
                        Text(updater.lastUpdateCheckDate.map {
                            $0.formatted(date: .abbreviated, time: .shortened)
                        } ?? "Never")
                        .foregroundStyle(.secondary)
                        Button("Check Now") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.isEnabled = newValue
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }

                if service.access == .denied {
                    LabeledContent("Reminders access") {
                        Button("Open System Settings…") {
                            let url = URL(
                                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                            )!
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            if service.access == .undetermined {
                await service.requestAccess()
            } else if service.access == .granted {
                service.loadLists()
            }
        }
    }
}
