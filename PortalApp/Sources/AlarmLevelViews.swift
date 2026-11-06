import Observation
import PortalKit
import SwiftUI

/// AlarmLevelPreference is which levels the active alarm lists show, kept on this device. Every list and every count reads the one
/// choice, so a level turned on in one place is on in all of them.
@MainActor
@Observable
final class AlarmLevelPreference {
    static let shared = AlarmLevelPreference()
    static let storageKey = "activeAlarmLevels"

    var filter: AlarmLevelFilter {
        didSet { UserDefaults.standard.set(filter.storedText, forKey: Self.storageKey) }
    }

    /// Whether the server filters by level too (it has the feature). An older server's lists show every level, as they always did.
    var isAvailable = false

    /// The filter the lists apply: the person's choice, or every level while the server does not have the feature.
    var activeFilter: AlarmLevelFilter { isAvailable ? filter : AlarmLevelFilter(selectedLevels: Set(AlarmLevel.allCases)) }

    private init() {
        filter = AlarmLevelFilter(storedText: UserDefaults.standard.string(forKey: Self.storageKey))
    }
}

extension AlarmLevel {
    var title: LocalizedStringKey {
        switch self {
        case .critical: "Critical"
        case .error: "Error"
        case .warning: "Warning"
        case .info: "Info"
        }
    }
}

/// AlarmLevelBar is the level filter above an active alarm list: one chip for each level with how many alarms the list has at it.
/// The chips are tap targets of the row and not buttons, so one tap turns on one level.
struct AlarmLevelBar: View {
    let alarms: [SiteAlarm]
    private let preference = AlarmLevelPreference.shared

    var body: some View {
        let counts = AlarmLevelFilter.counts(alarms)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AlarmLevel.allCases) { level in
                    chip(level, count: counts[level] ?? 0)
                }
            }
        }
        .accessibilityIdentifier("alarmLevelBar")
    }

    private func chip(_ level: AlarmLevel, count: Int) -> some View {
        let isOn = preference.filter.selectedLevels.contains(level)
        return HStack(spacing: 6) {
            Text(level.title)
            Text(count.formatted()).monospacedDigit().foregroundStyle(isOn ? Color.onAccent.opacity(0.85) : Color.secondary)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isOn ? Color.onAccent : Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
        .frame(minHeight: 44)
        .rowTapTarget { preference.filter.toggle(level) }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
        .accessibilityIdentifier("alarmLevel.\(level.rawValue)")
    }
}

/// AlarmLevelEmptyNote says why a list of active alarms shows none: they are all at levels the filter has off.
struct AlarmLevelEmptyNote: View {
    let hiddenCount: Int

    var body: some View {
        Text("No active alarms at these levels. \(hiddenCount) at other levels.")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("alarmLevelEmptyNote")
    }
}

/// ActiveAlarmRows is the filter, then the alarms at the chosen levels, or why there are none. `limit` caps the rows (the site page
/// shows the first few and the rest on a page of their own). It is built into the page's own list, not drawn as a view of its own.
@MainActor
enum ActiveAlarmRows {
    @ViewBuilder
    static func rows(_ alarms: [SiteAlarm], controllers: [ControllerSummary], limit: Int? = nil) -> some View {
        let preference = AlarmLevelPreference.shared
        let filter = preference.activeFilter
        let shown = filter.visible(alarms)
        if preference.isAvailable { AlarmLevelBar(alarms: alarms) }
        if shown.isEmpty {
            if !alarms.isEmpty { AlarmLevelEmptyNote(hiddenCount: filter.hiddenCount(alarms)) }
        } else {
            ForEach(limit.map { Array(shown.prefix($0)) } ?? shown) { alarm in SiteRows.alarmLink(alarm, controllers: controllers) }
        }
    }
}
