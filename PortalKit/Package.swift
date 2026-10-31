// swift-tools-version: 6.0

// PortalKit is everything in the iPhone app that is not a screen: the
// server address, sign-in, the GraphQL connection, the subscription feed and
// the transcript. It builds on Linux as well, so its tests run without a Mac.

import PackageDescription

let package = Package(
    name: "PortalKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "PortalKit", targets: ["PortalKit"])
    ],
    dependencies: [
        // CryptoKit is Apple's; Linux gets the same API from swift-crypto.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.0")
    ],
    targets: [
        .target(
            name: "PortalKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
            ]),
        .testTarget(name: "PortalKitTests", dependencies: ["PortalKit"]),
    ]
)
