import Foundation

/// VirtualControllerSnapshot is a saved state of a virtual controller that it can be restored to.
public struct VirtualControllerSnapshot: Decodable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let virtualControllerId: String?
    public let comment: String?
    /// `pending`, `ready`, `restoring`, `error` and so on, as the server says.
    public let status: String?
    public let statusMessage: String?
    public let createdAt: String?
    public let restoreRequestedAt: String?
    public let sourceSize: String?
    public let restoreSizeBytes: Int64?

    public init(
        id: String, virtualControllerId: String? = nil, comment: String? = nil, status: String? = "ready", statusMessage: String? = nil, createdAt: String? = nil,
        restoreRequestedAt: String? = nil, sourceSize: String? = nil, restoreSizeBytes: Int64? = nil
    ) {
        self.id = id
        self.virtualControllerId = virtualControllerId
        self.comment = comment
        self.status = status
        self.statusMessage = statusMessage
        self.createdAt = createdAt
        self.restoreRequestedAt = restoreRequestedAt
        self.sourceSize = sourceSize
        self.restoreSizeBytes = restoreSizeBytes
    }

    public var date: Date? { PortalDate.parse(createdAt) }
    public var isReady: Bool { status == "ready" }
    /// A snapshot can be restored only when it is ready.
    public var canRestore: Bool { isReady }
    public var shownName: String { (comment ?? "").isEmpty ? id : comment! }
}

extension Documents {
    static let snapshotFields = "id virtualControllerId comment status statusMessage createdAt restoreRequestedAt sourceSize restoreSizeBytes"

    public static let listVirtualControllerSnapshots = """
        query ListVirtualControllerSnapshots($virtualControllerId: String, $options: ListOptionsInput) {
          ListVirtualControllerSnapshots(virtualControllerId: $virtualControllerId, options: $options) { snapshots { \(snapshotFields) } meta { totalCount } }
        }
        """

    public static let createVirtualControllerSnapshot = """
        mutation CreateVirtualControllerSnapshot($virtualControllerId: String, $comment: String) {
          CreateVirtualControllerSnapshot(virtualControllerId: $virtualControllerId, comment: $comment) { virtualControllerSnapshot { \(snapshotFields) } }
        }
        """

    public static let restoreVirtualControllerSnapshot = """
        mutation RestoreVirtualControllerSnapshot($virtualControllerSnapshotId: String) {
          RestoreVirtualControllerSnapshot(virtualControllerSnapshotId: $virtualControllerSnapshotId) { virtualControllerSnapshot { \(snapshotFields) } }
        }
        """

    public static let modifyVirtualControllerSnapshot = """
        mutation ModifyVirtualControllerSnapshot($virtualControllerSnapshotId: String, $comment: String) {
          ModifyVirtualControllerSnapshot(virtualControllerSnapshotId: $virtualControllerSnapshotId, comment: $comment) { virtualControllerSnapshot { \(snapshotFields) } }
        }
        """

    public static let destroyVirtualControllerSnapshot = """
        mutation DestroyVirtualControllerSnapshot($virtualControllerSnapshotId: String) {
          DestroyVirtualControllerSnapshot(virtualControllerSnapshotId: $virtualControllerSnapshotId) { virtualControllerSnapshot { \(snapshotFields) } }
        }
        """

    static var snapshotDocuments: [String] {
        [listVirtualControllerSnapshots, createVirtualControllerSnapshot, restoreVirtualControllerSnapshot, modifyVirtualControllerSnapshot, destroyVirtualControllerSnapshot]
    }
}

extension Connection {
    /// Every snapshot of a virtual controller, newest first, paged until the total the server reports.
    public func snapshots(virtualControllerId: String, pageSize: Int = 100) async throws -> [VirtualControllerSnapshot] {
        struct Answer: Decodable, Sendable {
            struct Meta: Decodable, Sendable { let totalCount: Int? }
            struct List: Decodable, Sendable {
                let snapshots: [VirtualControllerSnapshot]?
                let meta: Meta?
            }
            let ListVirtualControllerSnapshots: List
        }
        var collected: [VirtualControllerSnapshot] = []
        while true {
            let variables: [String: JSONValue] = [
                "virtualControllerId": .string(virtualControllerId),
                "options": .object(["first": .number(Double(pageSize)), "after": .number(Double(collected.count))]),
            ]
            let list = try await execute(Documents.listVirtualControllerSnapshots, variables: variables, as: Answer.self).ListVirtualControllerSnapshots
            let page = list.snapshots ?? []
            collected += page
            if page.isEmpty { break }
            if let total = list.meta?.totalCount, collected.count >= total { break }
            if page.count < pageSize, list.meta?.totalCount == nil { break }
        }
        return collected.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private struct SnapshotAnswer: Decodable, Sendable {
        let virtualControllerSnapshot: VirtualControllerSnapshot
    }

    public func createSnapshot(virtualControllerId: String, comment: String) async throws -> VirtualControllerSnapshot {
        struct Answer: Decodable, Sendable { let CreateVirtualControllerSnapshot: SnapshotAnswer }
        return try await execute(
            Documents.createVirtualControllerSnapshot, variables: ["virtualControllerId": .string(virtualControllerId), "comment": .string(comment)], as: Answer.self
        ).CreateVirtualControllerSnapshot.virtualControllerSnapshot
    }

    public func restoreSnapshot(id: String) async throws {
        _ = try await execute(Documents.restoreVirtualControllerSnapshot, variables: ["virtualControllerSnapshotId": .string(id)], as: JSONValue.self)
    }

    public func renameSnapshot(id: String, comment: String) async throws -> VirtualControllerSnapshot {
        struct Answer: Decodable, Sendable { let ModifyVirtualControllerSnapshot: SnapshotAnswer }
        return try await execute(
            Documents.modifyVirtualControllerSnapshot, variables: ["virtualControllerSnapshotId": .string(id), "comment": .string(comment)], as: Answer.self
        ).ModifyVirtualControllerSnapshot.virtualControllerSnapshot
    }

    public func destroySnapshot(id: String) async throws {
        _ = try await execute(Documents.destroyVirtualControllerSnapshot, variables: ["virtualControllerSnapshotId": .string(id)], as: JSONValue.self)
    }
}
