// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AkhnaFinKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "AkhnaFinCore", targets: ["AkhnaFinCore"]),
        .library(name: "ServiceInterfaces", targets: ["ServiceInterfaces"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Services", targets: ["Services"])
    ],
    targets: [
        .target(name: "AkhnaFinCore"),
        .target(name: "ServiceInterfaces", dependencies: ["AkhnaFinCore"]),
        .target(name: "Persistence", dependencies: ["AkhnaFinCore", "ServiceInterfaces"]),
        .target(name: "Services", dependencies: ["AkhnaFinCore", "ServiceInterfaces"]),
        .testTarget(
            name: "AkhnaFinCoreTests",
            dependencies: ["AkhnaFinCore"]
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
