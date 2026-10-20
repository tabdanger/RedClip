// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

// Red Clip runs on iPad and iPhone (portrait face on iPhone). The AUv3 plug-in (for Logic Pro, GarageBand, AUM...) is built on
// GitHub from the Xcode project in ../xcode, from these same files plus ../AUv3.
let package = Package(
    name: "Red Clip",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Red Clip",
            targets: ["AppModule"],
            bundleIdentifier: "com.tabdanger.redclip",
            displayVersion: "1.0.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.red),
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .landscapeRight(.when(deviceFamilies: [.pad])),
                .landscapeLeft(.when(deviceFamilies: [.pad])),
                .portrait,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            appCategory: .music,
            additionalInfoPlistContentFilePath: "Info.plist"
        )
    ],
    dependencies: [
        // Lock-free atomics for the values the audio thread and the UI share (SharedMemory.swift).
        .package(url: "https://github.com/apple/swift-atomics.git", "1.2.0"..<"2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: ".",
            exclude: [
                "Info.plist"
            ],
            resources: [.process("Resources")]
        )
    ]
)
