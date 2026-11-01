import Foundation

/// The verbs a viewer holds at a virtual controller's site, as the server names them.
public enum VirtualControllerCapability {
    public static let modify = "virtual_controller:modify"
    public static let destroy = "virtual_controller:destroy"
}

extension VirtualControllerSummary {
    public var isPaused: Bool { !(pausedAt ?? "").isEmpty || status == "paused" }
    private var isGone: Bool { status == "destroyed" || status == "destroying" }

    /// Editing and pausing need `virtual_controller:modify`; a virtual controller being destroyed offers nothing.
    public var canModify: Bool { can(VirtualControllerCapability.modify) && !isGone }
    public var canDestroy: Bool { can(VirtualControllerCapability.destroy) && !isGone }
    /// Pause or resume is offered while it runs or is paused, not while it is still being made or has failed.
    public var canTogglePause: Bool { canModify && (isRunning || isPaused) }
}

/// VirtualControllerSize is a size the server offers a virtual controller in.
public struct VirtualControllerSize: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let displayName: String?
    public let diskCapacityBytes: Int64?
    public var id: String { name }
    public var shownName: String { (displayName ?? "").isEmpty ? name : displayName! }
}

extension Documents {
    static let virtualControllerFields = "id name comment siteId region status statusMessage viewerCapabilities releaseId releaseImageId pausedAt size product"

    public static let setVirtualControllersPaused = """
        mutation SetVirtualControllersPaused($virtualControllerIds: [String], $paused: Boolean) {
          SetVirtualControllersPaused(virtualControllerIds: $virtualControllerIds, paused: $paused) { virtualControllerIds }
        }
        """

    public static let modifyVirtualController = """
        mutation ModifyVirtualController($virtualControllerId: String, $virtualController: VirtualControllerInput) {
          ModifyVirtualController(virtualControllerId: $virtualControllerId, virtualController: $virtualController) {
            virtualController { \(virtualControllerFields) }
          }
        }
        """

    public static let destroyVirtualController = """
        mutation DestroyVirtualController($virtualControllerId: String) {
          DestroyVirtualController(virtualControllerId: $virtualControllerId) { virtualController { \(virtualControllerFields) } }
        }
        """

    public static let getVirtualController = """
        query GetVirtualController($virtualControllerId: String) { GetVirtualController(virtualControllerId: $virtualControllerId) { \(virtualControllerFields) } }
        """

    public static let listVirtualControllerSizes = """
        query ListVirtualControllerSizes { ListVirtualControllerSizes { name displayName diskCapacityBytes } }
        """

    static var virtualControllerManagementDocuments: [String] {
        [setVirtualControllersPaused, modifyVirtualController, destroyVirtualController, getVirtualController, listVirtualControllerSizes]
    }
}

extension Connection {
    public func virtualController(id: String) async throws -> VirtualControllerSummary {
        struct Answer: Decodable, Sendable { let GetVirtualController: VirtualControllerSummary }
        return try await execute(Documents.getVirtualController, variables: ["virtualControllerId": .string(id)], as: Answer.self).GetVirtualController
    }

    /// Pauses or resumes one virtual controller.
    public func setVirtualControllerPaused(id: String, paused: Bool) async throws {
        _ = try await execute(
            Documents.setVirtualControllersPaused, variables: ["virtualControllerIds": .array([.string(id)]), "paused": .bool(paused)], as: JSONValue.self)
    }

    /// Changes the fields given; a field left nil stays as it is.
    public func modifyVirtualController(id: String, name: String? = nil, comment: String? = nil, size: String? = nil) async throws -> VirtualControllerSummary {
        struct Answer: Decodable, Sendable {
            struct Result: Decodable, Sendable { let virtualController: VirtualControllerSummary }
            let ModifyVirtualController: Result
        }
        var input: [String: JSONValue] = [:]
        if let name { input["name"] = .string(name) }
        if let comment { input["comment"] = .string(comment) }
        if let size { input["size"] = .string(size) }
        return try await execute(
            Documents.modifyVirtualController, variables: ["virtualControllerId": .string(id), "virtualController": .object(input)], as: Answer.self
        ).ModifyVirtualController.virtualController
    }

    public func destroyVirtualController(id: String) async throws {
        _ = try await execute(Documents.destroyVirtualController, variables: ["virtualControllerId": .string(id)], as: JSONValue.self)
    }

    public func virtualControllerSizes() async throws -> [VirtualControllerSize] {
        struct Answer: Decodable, Sendable { let ListVirtualControllerSizes: [VirtualControllerSize]? }
        return try await execute(Documents.listVirtualControllerSizes, as: Answer.self).ListVirtualControllerSizes ?? []
    }
}
