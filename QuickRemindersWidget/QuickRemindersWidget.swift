import SwiftUI
import WidgetKit

struct FilterWidget: Widget {
    static let kind = "QuickRemindersFilterWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectFilterIntent.self,
            provider: FilterTimelineProvider()
        ) { entry in
            FilterWidgetView(entry: entry)
        }
        .configurationDisplayName("Filter")
        .description("Show the reminders matching one of your saved filters.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // The rows already sit in a padded stack; the default margins would
        // push the small family down to two visible rows.
        .contentMarginsDisabled()
    }
}

@main
struct QuickRemindersWidgetBundle: WidgetBundle {
    var body: some Widget {
        FilterWidget()
    }
}
