// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RezekiKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "RezekiCore", targets: ["RezekiCore"]),
        .library(name: "ServiceInterfaces", targets: ["ServiceInterfaces"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "TransactionsFeature", targets: ["TransactionsFeature"])
    ],
    targets: [
        .target(name: "RezekiCore"),
        .target(name: "ServiceInterfaces", dependencies: ["RezekiCore"]),
        .target(name: "Persistence", dependencies: ["RezekiCore", "ServiceInterfaces"]),
        .target(name: "DesignSystem", dependencies: ["RezekiCore"]),
        .target(
            name: "TransactionsFeature",
            dependencies: ["RezekiCore", "ServiceInterfaces", "Persistence", "DesignSystem"]
        ),
        .testTarget(
            name: "RezekiCoreTests",
            dependencies: ["RezekiCore"]
        ),
        .testTarget(
            name: "ServiceInterfacesTests",
            dependencies: ["ServiceInterfaces"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"]
        ),
        .testTarget(
            name: "TransactionsFeatureTests",
            dependencies: ["TransactionsFeature"]
        )
    ]
)
