import SwiftUI
import UniformTypeIdentifiers

/// The standalone app: the faceplate with the transport strip under it, scaled to fit the screen.
@MainActor
struct AppRootView: View {
    @ObservedObject var audio: AudioController
    @ObservedObject var face: FaceModel

    /// iPad: the faceplate with its transport strip picture under it. iPhone: the portrait face,
    /// whose transport is part of the picture. Same controls, same behaviour.
    let layout = PlateLayout.current

    var body: some View {
        GeometryReader { geo in
            let total = layout.canvas
            let scale = min(geo.size.width / total.width, geo.size.height / total.height)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    FaceplateView(face: face, params: face.params, layout: layout)
                    if let strip = layout.strip {
                        Image(face.theme.image(strip)).resizable().interpolation(.high)
                            .frame(width: total.width, height: total.height - layout.size.height)
                    }
                }
                transport
            }
            .frame(width: total.width, height: total.height, alignment: .topLeading)
            .helpBubbles(face, scale: layout.bubbleScale)
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

    // MARK: Transport (Load / Play / Export) — the picture's own buttons, with live labels on top.
    // Rectangles are canvas pixels from the layout.

    private var T: PlateLayout.Transport { layout.transport }

    private var transport: some View {
        ZStack(alignment: .topLeading) {
            // PLAY / PAUSE (spacebar too)
            Button { audio.togglePlay() } label: {
                HStack(spacing: T.font * 0.62) {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill").font(.system(size: T.font * 1.06, weight: .bold))
                    Text(audio.isPlaying ? "PAUSE" : "PLAY").font(.system(size: T.font, weight: .semibold)).tracking(T.font * 0.1)
                }
                .foregroundStyle(audio.isPlaying ? Plate.glow : face.theme.text)
                .frame(width: T.play.width, height: T.play.height).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .helpTarget(.play, face).place(T.play)

            HitArea { face.importRequested = true }
                .helpTarget(.load, face).place(T.load)
            samplesMenu
                .helpTarget(.samples, face).place(T.samples)
            HitArea { audio.loadDemo() }
                .helpTarget(.demo, face).place(T.demo)

            Text(audio.fileName)
                .font(.system(size: T.font, weight: .medium))
                .foregroundStyle(face.theme.text)
                .lineLimit(1)
                .frame(width: T.fileName.width, alignment: .leading)
                .place(T.fileName)

            // progress along the picture's groove; drag to seek
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                GeometryReader { geo in
                    let w = geo.size.width
                    let p = CGFloat(audio.progress)
                    let dot = T.font * 0.7
                    ZStack(alignment: .leading) {
                        Capsule().fill(Plate.glow.opacity(0.85)).frame(width: max(3, p * w), height: 3)
                            .shadow(color: Plate.glow, radius: 3)
                        Circle().fill(Plate.glow).frame(width: dot, height: dot)
                            .shadow(color: Plate.glow, radius: 5)
                            .offset(x: max(0, p * w - dot / 2))
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        audio.seek(to: Double(min(max(g.location.x / w, 0), 1)))
                    })
                }
            }
            .place(T.progress)

            Group {
                if audio.isBusy {
                    ProgressView().tint(Plate.glow)
                } else if let url = audio.exportURL {
                    ShareLink(item: url) { stripLegend("square.and.arrow.up", "SHARE") }
                } else {
                    Button { audio.export() } label: { stripLegend("square.and.arrow.up", "EXPORT") }
                        .buttonStyle(.plain)
                }
            }
            .helpTarget(.export, face).place(T.export)
        }
        .frame(width: layout.canvas.width, height: layout.canvas.height, alignment: .topLeading)
    }

    private func stripLegend(_ icon: String, _ title: String) -> some View {
        HStack(spacing: T.font * 0.56) {
            Image(systemName: icon).font(.system(size: T.font, weight: .semibold))
            Text(title).font(.system(size: T.font, weight: .semibold)).tracking(T.font * 0.1)
        }
        .foregroundStyle(face.theme.text)
        .frame(width: T.export.width, height: T.export.height).contentShape(Rectangle())
    }

    /// Everything in On My iPad › Red Clip › Samples.
    private var samplesMenu: some View {
        Menu {
            if audio.samples.isEmpty {
                Text(UIDevice.current.userInterfaceIdiom == .phone
                     ? "Put audio files in Files › On My iPhone › Red Clip › Samples"
                     : "Put audio files in Files › On My iPad › Red Clip › Samples")
            } else {
                ForEach(audio.samples, id: \.self) { url in
                    Button(SampleLibrary.relativeName(url)) { audio.load(url: url) }
                }
            }
            Divider()
            Button { audio.refreshSamples() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        } label: {
            Color.clear.contentShape(Rectangle())   // the SAMPLES legend is in the picture
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
