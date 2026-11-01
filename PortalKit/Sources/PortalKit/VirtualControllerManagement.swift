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

/// VirtualControllerProduct is a kind of virtual controller the server can make.
public struct VirtualControllerProduct: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let displayName: String?
    public var id: String { name }
    public var shownName: String { (displayName ?? "").isEmpty ? name : displayName! }
}

/// VirtualControllerRegion is a region a virtual controller can run in.
public struct VirtualControllerRegion: Decodable, Equatable, Identifiable, Sendable {
    public let region: String
    public let isLocal: Bool?
    public var id: String { region }
}

/// VirtualControllerOptions are the choices the create form offers.
public struct VirtualControllerOptions: Equatable, Sendable {
    public var sizes: [VirtualControllerSize] = []
    public var products: [VirtualControllerProduct] = []
    public var regions: [VirtualControllerRegion] = []

    public init() {}

    /// The region to start on: the one marked local, else the first.
    public var defaultRegion: String? { (regions.first { $0.isLocal == true } ?? regions.first)?.region }
}

public enum VirtualControllerCreateAccess {
    /// Making one needs `virtual_controller:create` at the site; the person's own permissions tell whether it is worth offering.
    /// An organization's operators and platform administrators may; the server checks again on every create.
    public static func canOffer(permissions: [String]) -> Bool {
        permissions.contains("virtual_controller:create") || permissions.contains("organization:operate-all") || permissions.contains("platform:administer")
    }
}

extension Documents {
    public static let listVirtualControllerProducts = """
        query ListVirtualControllerProducts { ListVirtualControllerProducts { name displayName } }
        """

    public static let listVirtualControllerRegions = """
        query ListVirtualControllerRegions { ListVirtualControllerRegions { region isLocal } }
        """

    public static let createVirtualController = """
        mutation CreateVirtualController($siteId: String, $virtualController: VirtualControllerInput) {
          CreateVirtualController(siteId: $siteId, virtualController: $virtualController) { virtualController { \(virtualControllerFields) } }
        }
        """

    static var virtualControllerCreateDocuments: [String] { [listVirtualControllerProducts, listVirtualControllerRegions, createVirtualController] }
}

extension Connection {
    public func virtualControllerOptions() async throws -> VirtualControllerOptions {
        struct Products: Decodable, Sendable { let ListVirtualControllerProducts: [VirtualControllerProduct]? }
        struct Regions: Decodable, Sendable { let ListVirtualControllerRegions: [VirtualControllerRegion]? }
        var options = VirtualControllerOptions()
        options.sizes = try await virtualControllerSizes()
        options.products = try await execute(Documents.listVirtualControllerProducts, as: Products.self).ListVirtualControllerProducts ?? []
        options.regions = try await execute(Documents.listVirtualControllerRegions, as: Regions.self).ListVirtualControllerRegions ?? []
        return options
    }

    public func createVirtualController(
        siteId: String, name: String, comment: String, size: String, product: String?, region: String?
    ) async throws -> VirtualControllerSummary {
        struct Answer: Decodable, Sendable {
            struct Result: Decodable, Sendable { let virtualController: VirtualControllerSummary }
            let CreateVirtualController: Result
        }
        var input: [String: JSONValue] = ["name": .string(name), "comment": .string(comment), "size": .string(size)]
        if let product, !product.isEmpty { input["product"] = .string(product) }
        if let region, !region.isEmpty { input["region"] = .string(region) }
        return try await execute(
            Documents.createVirtualController, variables: ["siteId": .string(siteId), "virtualController": .object(input)], as: Answer.self
        ).CreateVirtualController.virtualController
    }
}
