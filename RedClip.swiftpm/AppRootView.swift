import SwiftUI
import UniformTypeIdentifiers

/// The standalone app: the faceplate with the transport strip under it, scaled to fit the screen.
@MainActor
struct AppRootView: View {
    @ObservedObject var audio: AudioController
    @ObservedObject var face: FaceModel

    let stripHeight: CGFloat = 84

    var body: some View {
        GeometryReader { geo in
            let total = CGSize(width: FaceplateView.size.width, height: FaceplateView.size.height + stripHeight)
            let scale = min(geo.size.width / total.width, geo.size.height / total.height)
            VStack(spacing: 0) {
                FaceplateView(face: face, params: face.params)
                transportStrip.frame(width: total.width, height: stripHeight)
            }
            .frame(width: total.width, height: total.height)
            .helpBubbles(face)
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $face.importRequested, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { audio.load(url: url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            audio.refreshSamples()
        }
        .alert("Red Clip", isPresented: Binding(get: { audio.errorMessage != nil },
                                                set: { if !$0 { audio.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(audio.errorMessage ?? "")
        }
    }

    // MARK: Transport strip (below the face)

    private var transportStrip: some View {
        HStack(spacing: 14) {
            stripButton(audio.isPlaying ? "stop.fill" : "play.fill", audio.isPlaying ? "Stop" : "Play") {
                audio.togglePlay()
            }
            .helpTarget(.play, face)
            stripButton("folder", "Load") { face.importRequested = true }
                .helpTarget(.load, face)
            samplesMenu
                .helpTarget(.samples, face)
            stripButton("music.note", "Demo") { audio.loadDemo() }
                .helpTarget(.demo, face)

            Text(audio.fileName)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { _ in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(white: 0.14))
                        Capsule().fill(Theme.glow)
                            .frame(width: max(8, geo.size.width * audio.progress))
                            .shadow(color: Theme.glow.opacity(0.7), radius: 4)
                    }
                    .frame(height: 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        audio.seek(to: Double(g.location.x / geo.size.width))
                    })
                }
            }
            .frame(height: 44)

            if audio.isBusy {
                ProgressView().tint(Theme.glow).frame(width: 140)
            } else if let url = audio.exportURL {
                ShareLink(item: url) { stripLabel("square.and.arrow.up", "Share WAV") }
            } else {
                stripButton("square.and.arrow.down", "Export") { audio.export() }
                    .helpTarget(.export, face)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity)
        .background(Color(white: 0.06))
    }

    /// Everything in On My iPad › Red Clip › Samples.
    private var samplesMenu: some View {
        Menu {
            if audio.samples.isEmpty {
                Text("Put audio files in Files › On My iPad › Red Clip › Samples")
            } else {
                ForEach(audio.samples, id: \.self) { url in
                    Button(SampleLibrary.relativeName(url)) { audio.load(url: url) }
                }
            }
            Divider()
            Button { audio.refreshSamples() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        } label: {
            stripLabel("square.stack.3d.down.right", "Samples")
        }
    }

    private func stripButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { stripLabel(icon, title) }.buttonStyle(.plain)
    }

    private func stripLabel(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title.uppercased()).tracking(1.5)
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 18)
        .frame(height: 52)
        .well(radius: 9)
    }
}
