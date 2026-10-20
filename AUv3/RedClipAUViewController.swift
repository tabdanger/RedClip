import CoreAudioKit
import SwiftUI
import UIKit

// MARK: - The plug-in's window
//
// What Logic (or any host) shows when you open Red Clip's interface: the same faceplate as the
// app, without the transport strip (the host plays the audio), scaled to whatever size the host
// gives it. Closing the window doesn't stop the processing.

public final class RedClipAUViewController: AUViewController, AUAudioUnitFactory {
    private var unit: RedClipAudioUnit?
    private var hosting: UIHostingController<AnyView>?

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let made = try RedClipAudioUnit(componentDescription: componentDescription, options: [])
        unit = made
        DispatchQueue.main.async { [weak self] in self?.showFace() }
        return made
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // half the faceplate picture (iPad face 1448 x 997; iPhone face 852 x 1690 above its transport)
        let layout = PlateLayout.current
        preferredContentSize = CGSize(width: layout.size.width / 2, height: layout.pluginHeight / 2)
        showFace()
    }

    private func showFace() {
        guard isViewLoaded, hosting == nil, let unit else { return }
        let screen = PluginRootView(face: unit.face).preferredColorScheme(.dark)
        let host = UIHostingController(rootView: AnyView(screen))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hosting = host
    }
}

/// The faceplate scaled to the host's window. Knobs follow the host's automation.
@MainActor
struct PluginRootView: View {
    @ObservedObject var face: FaceModel
    let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let layout = PlateLayout.current
            let size = CGSize(width: layout.size.width, height: layout.pluginHeight)
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)
            FaceplateView(face: face, params: face.params, layout: layout)
                .helpBubbles(face, scale: layout.bubbleScale)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
        .onReceive(tick) { _ in face.params.syncFromShared() }
    }
}
