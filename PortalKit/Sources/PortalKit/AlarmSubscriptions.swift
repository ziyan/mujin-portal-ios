import Foundation

/// AlarmSubscription asks to be told about alarms at certain controllers from a minimum level up.
public struct AlarmSubscription: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let isEnabled: Bool?
    /// `notice`, `warning`, `error` or `critical`.
    public let minimumAlarmLevel: String?
    public let controllerIds: [String]?
    public let virtualControllerIds: [String]?

    public init(
        id: String, name: String? = nil, isEnabled: Bool? = true, minimumAlarmLevel: String? = "error", controllerIds: [String]? = nil, virtualControllerIds: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.minimumAlarmLevel = minimumAlarmLevel
        self.controllerIds = controllerIds
        self.virtualControllerIds = virtualControllerIds
    }

    public static let levels = ["notice", "warning", "error", "critical"]

    public func covers(controllerId: String) -> Bool { (controllerIds ?? []).contains(controllerId) }
    public func covers(virtualControllerId: String) -> Bool { (virtualControllerIds ?? []).contains(virtualControllerId) }
    public var shownName: String { (name ?? "").isEmpty ? id : name! }
}

extension Documents {
    static let alarmSubscriptionFields = "id name isEnabled minimumAlarmLevel controllerIds virtualControllerIds"

    public static let listAlarmSubscriptions = """
        query ListAlarmSubscriptions($options: ListOptionsInput) {
          ListAlarmSubscriptions(options: $options) { alarmSubscriptions { \(alarmSubscriptionFields) } meta { totalCount } }
        }
        """

    public static let createAlarmSubscription = """
        mutation CreateAlarmSubscription($name: String, $minimumAlarmLevel: String, $isEnabled: Boolean, $controllerIds: [String], $virtualControllerIds: [String]) {
          CreateAlarmSubscription(name: $name, minimumAlarmLevel: $minimumAlarmLevel, isEnabled: $isEnabled, controllerIds: $controllerIds, virtualControllerIds: $virtualControllerIds) {
            alarmSubscription { \(alarmSubscriptionFields) }
          }
        }
        """

    public static let modifyAlarmSubscription = """
        mutation ModifyAlarmSubscription($alarmSubscriptionId: String, $name: String, $minimumAlarmLevel: String, $isEnabled: Boolean, $controllerIds: [String], $virtualControllerIds: [String]) {
          ModifyAlarmSubscription(alarmSubscriptionId: $alarmSubscriptionId, name: $name, minimumAlarmLevel: $minimumAlarmLevel, isEnabled: $isEnabled, controllerIds: $controllerIds, virtualControllerIds: $virtualControllerIds) {
            alarmSubscription { \(alarmSubscriptionFields) }
          }
        }
        """

    public static let deleteAlarmSubscription = """
        mutation DeleteAlarmSubscription($alarmSubscriptionId: String) { DeleteAlarmSubscription(alarmSubscriptionId: $alarmSubscriptionId) { alarmSubscriptionId } }
        """

    static var alarmSubscriptionDocuments: [String] {
        [listAlarmSubscriptions, createAlarmSubscription, modifyAlarmSubscription, deleteAlarmSubscription]
    }
}

extension Connection {
    public func alarmSubscriptions() async throws -> [AlarmSubscription] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let alarmSubscriptions: [AlarmSubscription]? }
            let ListAlarmSubscriptions: List?
        }
        return try await execute(Documents.listAlarmSubscriptions, variables: ["options": .object(["first": .number(200)])], as: Answer.self)
            .ListAlarmSubscriptions?.alarmSubscriptions ?? []
    }

    public func createAlarmSubscription(name: String, minimumAlarmLevel: String, controllerIds: [String], virtualControllerIds: [String] = []) async throws {
        _ = try await execute(
            Documents.createAlarmSubscription,
            variables: [
                "name": .string(name), "minimumAlarmLevel": .string(minimumAlarmLevel), "isEnabled": .bool(true),
                "controllerIds": .array(controllerIds.map { .string($0) }), "virtualControllerIds": .array(virtualControllerIds.map { .string($0) }),
            ], as: JSONValue.self)
    }

    public func setAlarmSubscription(id: String, isEnabled: Bool) async throws {
        _ = try await execute(Documents.modifyAlarmSubscription, variables: ["alarmSubscriptionId": .string(id), "isEnabled": .bool(isEnabled)], as: JSONValue.self)
    }

    public func deleteAlarmSubscription(id: String) async throws {
        _ = try await execute(Documents.deleteAlarmSubscription, variables: ["alarmSubscriptionId": .string(id)], as: JSONValue.self)
    }
}
