import Foundation
import PortalKit

/// SiteViewDemo is the demo's screens for a controller left out of its site's views, a site's telemetry source and the alarm levels.
/// They are served only on their own screens, against a server that says it has the feature; every other screen is shot against one
/// that does not, which is how the app learns to show none of it. All the names are invented.
enum SiteViewDemo {
    /// Screens for the exclusion and the telemetry source.
    static let exclusionScreens: Set<String> = [
        "exclusion-site", "exclusion-site-nosource", "exclusion-cell", "exclusion-cell-source", "exclusion-controller", "exclusion-controller-included",
        "exclusion-controller-readonly", "exclusion-controllers",
    ]

    /// Screens for the alarm levels. They are served by the same server, which has the feature.
    static let alarmLevelScreens: Set<String> = ["alarm-levels", "alarm-levels-warnings", "alarm-levels-controller", "alarm-levels-list", "alarm-levels-critical"]

    static func owns(_ screen: String?) -> Bool { screen.map { exclusionScreens.contains($0) || alarmLevelScreens.contains($0) } ?? false }

    static let excludedControllerId = "controller04"
    static let sourceControllerId = "controller05"
    static let initiallyExcludedControllerIds: Set<String> = [excludedControllerId]

    /// The tab a screen opens on.
    static var section: AppSection { .site }

    /// The cells of the demo site, with the controllers each holds.
    static let cells: [(id: String, name: String, controllerIds: [String])] = [
        ("cell01", "Pick cell A", ["controller01", "controller03", "controller04"]),
        ("cell02", "Packing line", ["controller02", "controller05"]),
        ("cell03", "Spare cell", []),
    ]

    static func controllerIds(inCell cellId: String?) -> [String]? {
        guard let cellId else { return nil }
        return cells.first { $0.id == cellId }?.controllerIds ?? []
    }

    /// The summary of each controller for the last 24 hours: the site's telemetry source holds the whole site's, and the simulation
    /// controller's are large so that counting it would be plain to see.
    static let pickedParts: [String: Int] = ["controller01": 1_000, "controller02": 200, "controller03": 300, "controller04": 5_000, "controller05": 2_000]

    static func telemetrySummaries(requested: [String]?) -> [[String: Any]] {
        pickedParts.keys.sorted().filter { requested == nil || requested!.contains($0) }.map { id in
            let picked = pickedParts[id] ?? 0
            return [
                "controllerId": id, "isAvailable": true, "activeAlarmCount": 0,
                "totals": ["pickOperationCount": picked, "pickedPartCount": picked, "humanInterventionCount": 0, "directRobotThroughputPartsPerHour": 10.0],
            ]
        }
    }

    static func hasSource(_ screen: String?) -> Bool { screen != nil && screen != "exclusion-site-nosource" }

    static func sites(_ sites: [[String: Any]], screen: String?) -> [[String: Any]] {
        guard owns(screen), hasSource(screen) else { return sites }
        return sites.map { site in
            guard site["id"] as? String == "site01" else { return site }
            var changed = site
            changed["telemetrySourceControllerId"] = sourceControllerId
            return changed
        }
    }

    static func controllerRows(excluded: Set<String>) -> [[String: Any]] {
        func row(_ id: String, _ comment: String, capabilities: [String], isOnline: Bool = true) -> [String: Any] {
            [
                "id": id, "comment": comment, "siteId": "site01", "organizationId": "organization01", "region": "us-1", "viewerCapabilities": capabilities,
                "releaseId": "release01", "connection": isOnline ? ["id": "connection-\(id)"] : NSNull(), "hypervisorState": ["version": "2026.10.2"],
                "isExcludedFromSiteViews": excluded.contains(id),
            ]
        }
        let editing = ["controller:connect", "controller:write", "controller:edit", "backup:delete"]
        return [
            row("controller01", "Pick station controller", capabilities: editing),
            row("controller02", "Packing line controller", capabilities: ["controller:connect"]),
            row("controller03", "Palletizer controller", capabilities: editing),
            row(excludedControllerId, "Simulation controller", capabilities: editing),
            row(sourceControllerId, "Warehouse execution controller", capabilities: editing),
        ]
    }

    /// The alarms of the level screens: every level, one in capitals, and one of a level nobody knows.
    static func levelAlarms(screen: String?, stamp: (TimeInterval) -> String) -> [[String: Any]] {
        func alarm(_ id: String, _ level: String, _ message: String, _ secondsAgo: TimeInterval) -> [String: Any] {
            ["logEntryId": id, "alarmLevel": level, "alarmMessage": message, "alarmStatus": "active", "occurredAt": stamp(secondsAgo), "originLabel": "controller01"]
        }
        if screen == "alarm-levels-warnings" {
            return [alarm("alarmEntry11", "warning", "Conveyor 2 is running slowly", 3_000), alarm("alarmEntry12", "WARNING", "Label stock is low", 5_000)]
        }
        return [
            alarm("alarmEntry01", "critical", "Safety scanner tripped at the dock", 600),
            alarm("alarmEntry02", "ERROR", "Gripper suction pressure is low", 1_200),
            alarm("alarmEntry03", "warning", "Conveyor 2 is running slowly", 3_000),
            alarm("alarmEntry04", "Warning", "Label stock is low", 5_000),
            alarm("alarmEntry05", "info", "Shift report is ready", 7_000),
            alarm("alarmEntry06", "severe", "A new kind of alarm", 9_000),
        ]
    }

    /// The controller a controller screen opens.
    static func controllerId(for screen: String?) -> String? {
        switch screen {
        case "exclusion-controller": excludedControllerId
        case "exclusion-controller-readonly": "controller02"
        // The last is on a server without the feature: the controller page still shows its own alarms.
        case "exclusion-controller-included", "alarm-levels-controller", "controller-own-alarms": "controller01"
        default: nil
        }
    }
}
