// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DynamicIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DynamicIsland", targets: ["DynamicIsland"])
    ],
    targets: [
        .target(
            name: "CRustCore",
            path: "Sources/CRustCore",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "DynamicIsland",
            dependencies: ["CRustCore"],
            path: "Sources/DynamicIsland",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "rust-core/target/release/libdynamic_island_core.a",
                    "-framework", "Security",
                    "-framework", "CoreFoundation",
                    "-framework", "SystemConfiguration",
                    "-framework", "Carbon",
                    "-framework", "Metal",
                    "-framework", "MetalKit",
                    "-framework", "QuartzCore",
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/DynamicIsland/Info.plist"
                ])
            ]
        )
    ]
)
