import SwiftUI

@main
struct RedClipApp: App {
    @StateObject private var audio = AudioController()

    var body: some Scene {
        WindowGroup {
            AppRootView(audio: audio, face: audio.face)
                // The iPhone and iPad art both run edge to edge, so the face fills the whole screen
                // instead of sitting inside the safe area with black bars.
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
        }
    }
}
