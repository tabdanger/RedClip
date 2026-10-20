import SwiftUI
import UniformTypeIdentifiers

/// The standalone app: the faceplate with the transport strip under it, scaled to fit the screen.
@MainActor
struct AppRootView: View {
    @ObservedObject var audio: AudioController
    @ObservedObject var face: FaceModel

    /// The transport strip is the bottom of the faceplate picture (RCStrip, 1448 x 89).
    let stripHeight: CGFloat = 89

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

    // MARK: Transport strip (below the face) — the picture's own strip, with live labels on top.
    // Coordinates are pixels in RCStrip (the faceplate picture's rows 997 to 1086).

    private var transportStrip: some View {
        ZStack(alignment: .topLeading) {
            Image(face.theme.image("RCStrip")).resizable().interpolation(.high)
                .frame(width: FaceplateView.size.width, height: stripHeight)

            // PLAY / PAUSE (spacebar too)
            Button { audio.togglePlay() } label: {
                HStack(spacing: 10) {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .bold))
                    Text(audio.isPlaying ? "PAUSE" : "PLAY").font(.system(size: 16, weight: .semibold)).tracking(1.6)
                }
                .foregroundStyle(audio.isPlaying ? Plate.glow : face.theme.text)
                .frame(width: 115, height: 45).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .helpTarget(.play, face).place(x: 65, y: 15, w: 115, h: 45)

            HitArea { face.importRequested = true }
                .helpTarget(.load, face).place(x: 193, y: 15, w: 115, h: 45)
            samplesMenu
                .helpTarget(.samples, face).place(x: 323, y: 15, w: 145, h: 45)
            HitArea { audio.loadDemo() }
                .helpTarget(.demo, face).place(x: 483, y: 15, w: 107, h: 45)

            Text(audio.fileName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(face.theme.text)
                .lineLimit(1)
                .frame(width: 165, alignment: .leading)
                .place(x: 607, y: 25, w: 165, h: 24)

            // progress along the picture's groove; drag to seek
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                GeometryReader { geo in
                    let w = geo.size.width
                    let p = CGFloat(audio.progress)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Plate.glow.opacity(0.85)).frame(width: max(3, p * w), height: 3)
                            .shadow(color: Plate.glow, radius: 3)
                        Circle().fill(Plate.glow).frame(width: 11, height: 11)
                            .shadow(color: Plate.glow, radius: 5)
                            .offset(x: max(0, p * w - 5.5))
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        audio.seek(to: Double(min(max(g.location.x / w, 0), 1)))
                    })
                }
            }
            .place(x: 790, y: 22, w: 436, h: 30)

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
            .helpTarget(.export, face).place(x: 1251, y: 15, w: 131, h: 45)
        }
        .frame(width: FaceplateView.size.width, height: stripHeight, alignment: .topLeading)
    }

    private func stripLegend(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
            Text(title).font(.system(size: 16, weight: .semibold)).tracking(1.6)
        }
        .foregroundStyle(face.theme.text)
        .frame(width: 131, height: 45).contentShape(Rectangle())
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
