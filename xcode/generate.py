#!/usr/bin/env python3
"""Writes the Info.plists for the Xcode build (app + AUv3 effect) from RedClip.swiftpm.

Run from the repository root on the build machine, then `xcodegen generate --spec xcode/project.yml`.
The app's Info.plist is what Swift Playgrounds generates from Package.swift, plus the extra keys
in RedClip.swiftpm/Info.plist, so the app built here matches the one Playgrounds builds. Prints the
version and build numbers for xcodebuild.
"""
import json
import os
import plistlib
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGE = os.path.join(ROOT, "RedClip.swiftpm", "Package.swift")
EXTRA = os.path.join(ROOT, "RedClip.swiftpm", "Info.plist")
OUT = os.path.join(ROOT, "xcode", "build")


def package_value(name):
    text = open(PACKAGE).read()
    match = re.search(name + r':\s*"([^"]*)"', text)
    if not match:
        sys.exit(f"Package.swift has no {name}")
    return match.group(1)


def main():
    version = package_value("displayVersion")
    build = os.environ.get("REDCLIP_BUILD") or package_value("bundleVersion")
    os.makedirs(OUT, exist_ok=True)

    orientations = [
        "UIInterfaceOrientationLandscapeRight",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationPortraitUpsideDown",
    ]
    # The keys Swift Playgrounds writes for Package.swift, including its odd nested UILaunchScreen.
    app = {
        "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "LSApplicationCategoryType": "public.app-category.music",
        "LSRequiresIPhoneOS": True,
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": True, "UISceneConfigurations": {}},
        "UIApplicationSupportsIndirectInputEvents": True,
        "UILaunchScreen": {"UILaunchScreen": {}},
        "UISupportedInterfaceOrientations~ipad": orientations,
        "UISupportedInterfaceOrientations~iphone": ["UIInterfaceOrientationPortrait"],
    }
    with open(EXTRA, "rb") as handle:
        app.update(plistlib.load(handle))

    # The Audio Unit's version: hosts keep a list of plug-ins and re-read one whose version
    # changed. 1.0.0 -> 0x010000.
    parts = [int(p) for p in (version.split(".") + ["0", "0"])[:3]]
    component_version = (parts[0] << 16) | (parts[1] << 8) | parts[2]
    plugin = {
        "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
        "CFBundleDisplayName": "Red Clip",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "NSExtension": {
            "NSExtensionAttributes": {
                "AudioComponents": [{
                    "description": "Red Clip mastering clipper",
                    "manufacturer": "Tdgr",
                    "name": "Tabdanger: Red Clip",
                    "sandboxSafe": True,
                    "subtype": "rclp",
                    "tags": ["Effects", "Dynamics"],
                    "type": "aufx",
                    "version": component_version,
                }],
            },
            "NSExtensionPointIdentifier": "com.apple.AudioUnit-UI",
            "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).RedClipAUViewController",
        },
    }

    # Each target's own copy of the Swift files and resources (see project.yml).
    package_dir = os.path.join(ROOT, "RedClip.swiftpm")
    # The plug-in has no app entry point, transport/player or sample library (the host plays the audio).
    app_only = {"RedClipApp.swift", "AppRootView.swift", "AudioController.swift", "SampleLibrary.swift"}
    for target, skip in (("app", set()), ("plugin", app_only), ("tests", app_only)):
        sources = os.path.join(OUT, target, "Sources")
        resources = os.path.join(OUT, target, "Resources")
        shutil.rmtree(sources, ignore_errors=True)
        shutil.rmtree(resources, ignore_errors=True)
        os.makedirs(sources)
        for name in sorted(os.listdir(package_dir)):
            if name.endswith(".swift") and name != "Package.swift" and name not in skip:
                shutil.copyfile(os.path.join(package_dir, name), os.path.join(sources, name))
        if target == "tests":
            # The tests drive the real plug-in (RedClipAudioUnit and its render block), so they
            # get their own copy of the AUv3 files too.
            auv3 = os.path.join(ROOT, "AUv3")
            for name in sorted(os.listdir(auv3)):
                if name.endswith(".swift"):
                    shutil.copyfile(os.path.join(auv3, name), os.path.join(sources, name))
        shutil.copytree(os.path.join(package_dir, "Resources"), resources)
        # Package.swift's `accentColor: .presetColor(.red)`: Playgrounds adds this colour to
        # the asset catalog under this name and points NSAccentColorName at it (project.yml
        # sets ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, which writes that key).
        accent = os.path.join(resources, "Assets.xcassets", "__PresetAccentColor.colorset")
        os.makedirs(accent)
        with open(os.path.join(accent, "Contents.json"), "w") as handle:
            json.dump({
                "colors": [{"color": {"platform": "universal", "reference": "systemRedColor"},
                            "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }, handle, indent=2)

    with open(os.path.join(OUT, "App-Info.plist"), "wb") as handle:
        plistlib.dump(app, handle)
    with open(os.path.join(OUT, "AU-Info.plist"), "wb") as handle:
        plistlib.dump(plugin, handle)
    print(f"MARKETING_VERSION={version}")
    print(f"CURRENT_PROJECT_VERSION={build}")
    print(f"AU_COMPONENT_VERSION={component_version}")


if __name__ == "__main__":
    main()
