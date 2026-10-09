// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

// Red Clip runs on iPad only. The AUv3 plug-in (for Logic Pro, GarageBand, AUM...) is built on
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
            supportedDeviceFamilies: [.pad],
            supportedInterfaceOrientations: [
                .landscapeRight,
                .landscapeLeft,
                .portrait,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            appCategory: .music,
            additionalInfoPlistContentFilePath: "Info.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            exclude: [
                "Info.plist"
            ],
            resources: [.process("Resources")]
        )
    ]
)
