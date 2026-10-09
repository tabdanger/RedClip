# Red Clip

A mastering clipper for iPad, as an app and as an **AUv3 effect** for Logic Pro for iPad,
GarageBand, AUM, Cubasis and other hosts.

- `RedClip.swiftpm` — the app. Opens in Swift Playgrounds on the iPad. Everything lives here.
- `AUv3/` — the plug-in wrapper (Swift Playgrounds can't build plug-ins, so GitHub builds it).
- `xcode/` — makes the Xcode project (app + plug-in) on GitHub's Macs from the files above.
- `.github/workflows/build.yml` — compiles everything on every push.
- `.github/workflows/upload.yml` — builds, signs and sends it to TestFlight (Actions tab › Run workflow).

## Using it in Logic Pro for iPad
Install from TestFlight, open the app once, then in Logic: track › Plug-ins › + ›
Audio Units › Tabdanger › **Red Clip**. Every control can be automated, the factory presets show
in Logic's preset menu, and the settings save with the project. POWER off passes audio straight
through. BYPASS compares against the dry track.

## Your own samples
Files › On My iPad › **Red Clip › Samples**. Anything you drop in there (WAV, AIFF, CAF, MP3,
M4A, AAC, FLAC, sub-folders too) shows up under **SAMPLES** in the app. Files picked with **LOAD**
from anywhere else get copied in there as well.

## Secrets (Settings › Secrets and variables › Actions)
Same four as MS26: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`.

## First upload
1. Actions › Upload Red Clip › Run workflow › **sign** — registers the bundle IDs
   `com.tabdanger.redclip` and `com.tabdanger.redclip.AUv3` and test-signs a build.
2. App Store Connect › Apps › + › New App, bundle ID `com.tabdanger.redclip`.
3. Run workflow › **upload**.
