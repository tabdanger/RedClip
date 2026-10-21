import SwiftUI

@main
struct RedClipApp: App {
    @StateObject private var audio = AudioController()

    var body: some Scene {
        WindowGroup {
            AppRootView(audio: audio, face: audio.face)
                // The iPhone art runs edge to edge (its top is the status-bar area), so it fills
                // the whole screen instead of sitting inside the safe area with black bars.
                .ignoresSafeArea(edges: UIDevice.current.userInterfaceIdiom == .phone ? .all : [])
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
        }
    }
}
