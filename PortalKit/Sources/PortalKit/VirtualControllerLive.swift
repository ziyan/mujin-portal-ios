import Foundation

extension Documents {
    public static let listVirtualControllerAlarms = """
        query ListVirtualControllerAlarms($virtualControllerId: String) {
          ListControllerActiveAlarms(virtualControllerId: $virtualControllerId) { alarms { alarmLevel alarmMessage alarmStatus occurredAt originLabel } }
        }
        """

    static var virtualControllerLiveDocuments: [String] { [listVirtualControllerAlarms] }
}

extension Connection {
    /// The alarms active on a virtual controller, worst first.
    public func virtualControllerAlarms(id: String) async throws -> [SiteAlarm] {
        struct Answer: Decodable, Sendable {
            struct Holder: Decodable, Sendable {
                struct Alarm: Decodable, Sendable {
                    let alarmLevel: String?
                    let alarmMessage: String?
                    let alarmStatus: String?
                    let occurredAt: String?
                    let originLabel: String?
                }
                let alarms: [Alarm]?
            }
            let ListControllerActiveAlarms: Holder?
        }
        let rows = try await execute(Documents.listVirtualControllerAlarms, variables: ["virtualControllerId": .string(id)], as: Answer.self).ListControllerActiveAlarms?.alarms ?? []
        return rows.map {
            SiteAlarm(controllerId: id, level: $0.alarmLevel ?? "", message: $0.alarmMessage ?? "", status: $0.alarmStatus ?? "", occurredAt: $0.occurredAt, originLabel: $0.originLabel)
        }.sorted { $0.severityRank < $1.severityRank }
    }
}
