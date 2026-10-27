import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Watches touches and pointer hovers over the faceplate without taking them, so every knob and
/// button keeps working while the "?" pop-ups are on. Its two recognizers sit on the window:
/// they never cancel or delay a touch and never recognize, they only report where the finger or
/// pointer is, converted into this view's (the faceplate's design-size) coordinates.
struct HelpProbe: UIViewRepresentable {
    var onTouch: (CGPoint?) -> Void   // down / moved; nil when lifted
    var onHover: (CGPoint?) -> Void   // nil when the pointer leaves

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onTouch = onTouch
        view.onHover = onHover
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) {
        view.detach()
    }

    final class ProbeView: UIView {
        var onTouch: (CGPoint?) -> Void = { _ in }
        var onHover: (CGPoint?) -> Void = { _ in }
        private let touches: TouchWatcher = {
            let w = TouchWatcher(target: nil, action: nil)
            w.cancelsTouchesInView = false
            w.delaysTouchesBegan = false
            w.delaysTouchesEnded = false
            return w
        }()
        private lazy var hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
        private weak var attached: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            touches.onTouch = { [weak self] p in
                guard let self else { return }
                self.onTouch(p.map { self.convert($0, from: nil) })
            }
            hover.cancelsTouchesInView = false
            window.addGestureRecognizer(touches)
            window.addGestureRecognizer(hover)
            attached = window
        }

        func detach() {
            attached?.removeGestureRecognizer(touches)
            attached?.removeGestureRecognizer(hover)
            attached = nil
        }

        @objc private func hovered(_ g: UIHoverGestureRecognizer) {
            switch g.state {
            case .began, .changed: onHover(g.location(in: self))
            default: onHover(nil)
            }
        }
    }
}

/// Follows the first finger down and reports it in window coordinates. It stays "possible" while
/// the finger is down and fails when it lifts, so it never wins over (or holds up) any control.
final class TouchWatcher: UIGestureRecognizer {
    var onTouch: (CGPoint?) -> Void = { _ in }
    private var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked == nil, let t = touches.first else { return }
        tracked = t
        onTouch(t.location(in: nil))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let t = tracked, touches.contains(t) { onTouch(t.location(in: nil)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lifted(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lifted(touches) }

    private func lifted(_ touches: Set<UITouch>) {
        guard let t = tracked, touches.contains(t) else { return }
        tracked = nil
        onTouch(nil)
        state = .failed
    }

    override func reset() {
        super.reset()
        tracked = nil
    }

    // Never stands in the way of another recognizer.
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
