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
        .library(name: "Services", targets: ["Services"])
    ],
    targets: [
        .target(name: "RezekiCore"),
        .target(name: "ServiceInterfaces", dependencies: ["RezekiCore"]),
        .target(name: "Persistence", dependencies: ["RezekiCore", "ServiceInterfaces"]),
        .target(name: "Services", dependencies: ["RezekiCore", "ServiceInterfaces"]),
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
            name: "ServicesTests",
            dependencies: ["Services"]
        )
    ]
)
