import SwiftUI

@main
struct RedClipApp: App {
    @StateObject private var audio = AudioController()

    var body: some Scene {
        WindowGroup {
            AppRootView(audio: audio, face: audio.face)
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
        }
    }
}
