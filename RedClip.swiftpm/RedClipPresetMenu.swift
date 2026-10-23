// Red Clip — the REDCLIP MENU: a compact machined-metal hardware panel for audio, presets and
// the faceplate finish. Requires the existing Red Clip types; not a standalone app.
// iOS 17+, SwiftUI. Opened from the preset name (Faceplate.swift) and the app's Samples key
// (AppRootView.swift), and the parallel mixer from the Mix value; hosted once per root, outside
// the scaled faceplate, by redClipPresetMenuHost.
// One page at a time inside one panel: pinned header (Back / title / Close), a scrolling list,
// and on the root page a pinned SETTINGS footer (Parallel Mixer, Faceplate).
import SwiftUI

enum RCMenuAnchor: Hashable { case presets, samples, mixer }

enum RCMenuPage: Equatable {
    case home
    case bank(String)
    case samples
    case faceplates
    case mixer

    var title: String {
        switch self {
        case .home: return "Menu"
        case .bank(let name): return name
        case .samples: return "Samples"
        case .faceplates: return "Faceplate"
        case .mixer: return "Parallel Mixer"
        }
    }
}

struct RCMenuRequest: Identifiable {
    let id = UUID()
    let page: RCMenuPage
    let anchor: RCMenuAnchor
}

@MainActor
extension FaceModel {
    func toggleRCMenu(page: RCMenuPage = .home, anchor: RCMenuAnchor = .presets) {
        if rcMenuRequest?.anchor == anchor {
            rcMenuRequest = nil
        } else {
            rcMenuRequest = RCMenuRequest(page: page, anchor: anchor)
        }
    }
}

private struct RCMenuAnchorKey: PreferenceKey {
    static var defaultValue: [RCMenuAnchor: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [RCMenuAnchor: Anchor<CGRect>],
                       nextValue: () -> [RCMenuAnchor: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Mark the visible trigger BEFORE .place(...); the anchor travels through scaling.
    /// VoiceOver focus returns to this trigger when the menu it opened closes.
    @MainActor
    func rcMenuAnchor(_ anchor: RCMenuAnchor, face: FaceModel) -> some View {
        modifier(RCMenuTrigger(anchor: anchor, face: face))
    }

    /// Install AFTER the faceplate's scaleEffect and final host-sized frame.
    @MainActor
    func redClipPresetMenuHost(face: FaceModel,
                               refreshSamples: (() -> Void)? = nil) -> some View {
        modifier(RCMenuHost(face: face, refreshSamples: refreshSamples))
    }
}

@MainActor
private struct RCMenuTrigger: ViewModifier {
    let anchor: RCMenuAnchor
    @ObservedObject var face: FaceModel
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: RCMenuAnchorKey.self, value: .bounds) { [anchor: $0] }
            .accessibilityFocused($focused)
            .onChange(of: face.rcMenuRequest?.anchor) { old, new in
                guard old == anchor, new == nil else { return }
                // The faceplate is hidden from VoiceOver while the menu is open; wait for it to return.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    focused = true
                }
            }
    }
}

@MainActor
private struct RCMenuHost: ViewModifier {
    @ObservedObject var face: FaceModel
    var refreshSamples: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(face.rcMenuRequest != nil)
            .overlayPreferenceValue(RCMenuAnchorKey.self) { anchors in
                GeometryReader { geometry in
                    if let request = face.rcMenuRequest {
                        let trigger = anchors[request.anchor].map { geometry[$0] }
                            ?? CGRect(x: geometry.size.width / 2,
                                      y: geometry.safeAreaInsets.top + 8, width: 0, height: 0)
                        let frame = RCMenuPlacement.frame(size: geometry.size,
                                                         safe: geometry.safeAreaInsets,
                                                         anchor: trigger,
                                                         largeText: typeSize >= .xxxLarge,
                                                         height: request.page == .mixer ? 430 : nil)
                        ZStack(alignment: .topLeading) {
                            // Invisible outside-tap catcher. It consumes the dismissal tap
                            // so a control underneath cannot turn on accidentally. No scrim, no blur.
                            Color.black.opacity(0.001)
                                .contentShape(Rectangle())
                                .onTapGesture { face.rcMenuRequest = nil }
                                .accessibilityHidden(true)

                            RCMenuPanel(face: face, params: face.params,
                                        initialPage: request.page,
                                        panelHeight: frame.height,
                                        refreshSamples: refreshSamples,
                                        close: { face.rcMenuRequest = nil })
                                .id(request.id)
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .transition(reduceMotion ? .opacity
                                    : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                        .zIndex(100)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14),
                       value: face.rcMenuRequest != nil)
            .onDisappear { face.rcMenuRequest = nil }
    }
}

/// Everything is measured in the actual host's points, never UIScreen bounds or device names.
/// Recomputes for rotation, keyboard avoidance, split view and AUv3 window resizing.
enum RCMenuPlacement {
    static let margin: CGFloat = 12

    /// A phone, a narrow iPad window or a small AUv3 view.
    static func isCompact(_ size: CGSize) -> Bool { size.width < 600 || size.height < 520 }

    /// `height`: a fixed panel height (the mixer), else the browser's height for this space.
    static func frame(size: CGSize, safe: EdgeInsets, anchor: CGRect,
                      largeText: Bool = false, height fixed: CGFloat? = nil) -> CGRect {
        let left = min(size.width, max(0, safe.leading) + margin)
        let top = min(size.height, max(0, safe.top) + margin)
        let right = max(left, size.width - max(0, safe.trailing) - margin)
        let bottom = max(top, size.height - max(0, safe.bottom) - margin)
        let availableWidth = max(0, right - left)
        let availableHeight = max(0, bottom - top)

        let compact = isCompact(size)
        let preferredWidth: CGFloat = (compact ? 320 : 364) + (largeText ? 60 : 0)
        let width = min(preferredWidth, availableWidth)
        var height = min(availableHeight, fixed ?? (compact ? 600 : 680))

        let x = min(max(anchor.midX - width / 2, left), max(left, right - width))
        let below = bottom - anchor.maxY - 8
        let above = anchor.minY - top - 8
        let y: CGFloat
        if below >= height {
            y = anchor.maxY + 8
        } else if below >= 320 {
            // Stay anchored under the trigger and scroll more instead of covering it.
            height = below
            y = anchor.maxY + 8
        } else if above >= height {
            y = anchor.minY - height - 8
        } else {
            // Not enough room either side: centre in the safe rectangle.
            y = top + (availableHeight - height) / 2
        }
        let clampedY = min(max(y, top), max(top, bottom - height))
        return CGRect(x: x, y: clampedY, width: width, height: height)
    }
}

/// Design tokens for the menu (shared by both finishes; only the metal frame changes).
enum RCMenuInk {
    static let surface = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x19 / 255)
    static let raised = Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x25 / 255)
    static let text = Color(red: 0xF2 / 255, green: 0xF0 / 255, blue: 0xED / 255)
    static let dim = Color(red: 0xA8 / 255, green: 0xA6 / 255, blue: 0xA3 / 255)
    static let accent = Color(red: 0xF4 / 255, green: 0x47 / 255, blue: 0x3D / 255)
    static let selection = Color(red: 0x3A / 255, green: 0x20 / 255, blue: 0x20 / 255)
    static let separator = Color(white: 0.17)
    static let rowHeight: CGFloat = 48
    static let headerHeight: CGFloat = 52
    static let gutter: CGFloat = 16
}

@MainActor
private struct RCMenuPanel: View {
    @ObservedObject var face: FaceModel
    @ObservedObject var params: ParamStore
    let panelHeight: CGFloat
    let refreshSamples: (() -> Void)?
    let close: () -> Void
    @State private var page: RCMenuPage
    @State private var presetSearch = ""
    @State private var sampleSearch = ""
    @FocusState private var searchFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = RCMenuInk.rowHeight

    init(face: FaceModel, params: ParamStore, initialPage: RCMenuPage, panelHeight: CGFloat,
         refreshSamples: (() -> Void)?, close: @escaping () -> Void) {
        self.face = face
        self.params = params
        self.panelHeight = panelHeight
        self.refreshSamples = refreshSamples
        self.close = close
        _page = State(initialValue: initialPage)
    }

    private var platinum: Bool { face.faceplate == .face1Platinum }
    private var presetQuery: String { presetSearch.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var sampleQuery: String { sampleSearch.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Pinned header + pinned footer (two rows) + at least three usable rows; otherwise the footer
    /// scrolls with the list as a deliberate fallback (short AUv3 views, very large text).
    private var pinsFooter: Bool {
        RCMenuInk.headerHeight + 12 + rowHeight * 0.7 + rowHeight * 5 <= panelHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            RCMenuHeader(page: page, platinum: platinum, titleFocused: $titleFocused,
                         back: { navigate(.home) }, close: close)
            well
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
        }
        .background { RCMenuMetal(platinum: platinum) }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(platinum ? 0.9 : 0.45),
                                                      Color.black.opacity(0.35)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: 1)
                .allowsHitTesting(false)
        }
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.9))
                .shadow(color: .black.opacity(0.55), radius: 16, x: 0, y: 10)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("RedClip menu")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear {
            titleFocused = true
            if page == .samples { refreshSamples?() }
        }
    }

    // MARK: Content well

    private var well: some View {
        VStack(spacing: 0) {
            ZStack {
                // The root list stays mounted under a sub-page, so its scroll position is kept
                // exactly when Back returns to it.
                homeList
                    .opacity(page == .home ? 1 : 0)
                    .allowsHitTesting(page == .home)
                    .accessibilityHidden(page != .home)
                if page == .mixer {
                    // Not in a scroll view, so the knobs' vertical drags are never taken for scrolling.
                    RCMixerPage(params: params)
                        .background(RCMenuInk.surface)
                } else if page != .home {
                    subpageList
                        .background(RCMenuInk.surface)
                }
            }
            if page == .home && pinsFooter {
                settingsSection
                    .overlay(alignment: .top) { Rectangle().fill(Color.black).frame(height: 1) }
            }
        }
        .background(RCMenuInk.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            // Inset: dark at the top lip, a hairline of light at the bottom.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.black.opacity(0.95), Color.white.opacity(0.18)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: 1.5)
                .allowsHitTesting(false)
        }
    }

    private var homeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                searchField(placeholder: "Search presets", text: $presetSearch)
                if presetQuery.isEmpty {
                    if !face.isPlugin {
                        sectionTitle("Audio")
                        importRow
                        RCMenuRow(title: "Samples", icon: "square.stack.3d.down.right", chevron: true) {
                            navigate(.samples)
                        }
                        RCMenuRow(title: "Demo Loop", icon: "music.note") {
                            face.loadDemo?()
                        }
                        .disabled(face.loadDemo == nil)
                    }
                    sectionTitle("Presets")
                    ForEach(Preset.banks, id: \.self) { bank in
                        RCMenuRow(title: bank, chevron: true,
                                  hint: "\(Preset.factory.filter { $0.bank == bank }.count) presets") {
                            navigate(.bank(bank))
                        }
                    }
                    if !pinsFooter { settingsSection }
                } else {
                    sectionTitle("All presets")
                    presetRows(bank: nil)
                }
            }
        }
        .scrollIndicators(.automatic)
        .scrollDismissesKeyboard(.interactively)
    }

    private var subpageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    switch page {
                    case .home, .mixer:
                        EmptyView()
                    case .bank(let bank):
                        presetRows(bank: bank)
                    case .samples:
                        sampleRows
                    case .faceplates:
                        ForEach(Faceplate.allCases, id: \.self) { finish in
                            RCMenuRow(title: finish.title, icon: "paintbrush.pointed",
                                      selected: face.faceplate == finish) {
                                // Only the finish changes; audio and parameters are untouched.
                                face.faceplate = finish
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.automatic)
            .scrollDismissesKeyboard(.interactively)
            .id(page.title)
            .onAppear {
                if case .bank(let bank) = page,
                   Preset.factory.indices.contains(params.presetIndex),
                   Preset.factory[params.presetIndex].bank == bank {
                    // Run after the bank's lazy list is mounted.
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo(params.presetIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Settings")
            RCMenuRow(title: "Parallel Mixer", icon: "slider.horizontal.2.square",
                      detail: params.mixUnlinked ? "Unlinked" : "Linked", chevron: true) {
                // reopens beside the Mix knob, sized for the mixer
                face.rcMenuRequest = RCMenuRequest(page: .mixer, anchor: .mixer)
            }
            RCMenuRow(title: "Faceplate", icon: "paintbrush.pointed", chevron: true,
                      separator: false, hint: face.faceplate.title) {
                navigate(.faceplates)
            }
        }
        .background(RCMenuInk.surface)
    }

    private var importRow: some View {
        RCMenuRow(title: "Import Audio from Files…", icon: "square.and.arrow.down") {
            // Close first so the system file picker never fights the menu; the app's existing
            // secure importer, loader, cancel and error handling do the rest.
            close()
            face.importRequested = true
        }
    }

    @ViewBuilder
    private func presetRows(bank: String?) -> some View {
        let indices = Preset.factory.indices.filter { index in
            let item = Preset.factory[index]
            return (bank == nil || item.bank == bank)
                && (bank != nil || presetQuery.isEmpty || item.name.localizedStandardContains(presetQuery)
                    || item.bank.localizedStandardContains(presetQuery))
        }
        if indices.isEmpty {
            emptyMessage("No matching presets", detail: "Try a name or category.")
        } else {
            ForEach(indices, id: \.self) { index in
                let item = Preset.factory[index]
                let selected = params.presetIndex == index
                RCMenuRow(title: item.name, subtitle: bank == nil ? item.bank : nil,
                          number: index + 1, selected: selected,
                          detail: selected && !matchesPreset(index) ? "Edited" : nil) {
                    // The app's real undo + parameter + AU notification path, once. The menu
                    // stays open for comparing presets; transport is never touched.
                    params.apply(index)
                    searchFocused = false
                }
                .id(index)
            }
        }
    }

    @ViewBuilder
    private var sampleRows: some View {
        if face.isPlugin {
            emptyMessage("Host audio", detail: "The host supplies audio in AUv3.")
        } else {
            searchField(placeholder: "Search samples", text: $sampleSearch)
            let items = face.sampleFiles.filter {
                sampleQuery.isEmpty || $0.name.localizedStandardContains(sampleQuery)
            }
            if items.isEmpty {
                emptyMessage(sampleQuery.isEmpty ? "No samples yet" : "No matching samples",
                             detail: sampleQuery.isEmpty ? "Import audio from Files to add a sample."
                                                         : "Try another filename.")
                if sampleQuery.isEmpty { importRow }
            } else {
                ForEach(items) { item in
                    RCMenuRow(title: item.name, icon: "waveform") {
                        face.loadSample?(item.url)
                        searchFocused = false
                    }
                    .disabled(face.loadSample == nil)
                }
            }
            if let refreshSamples {
                RCMenuRow(title: "Refresh List", icon: "arrow.clockwise", separator: false,
                          action: refreshSamples)
            }
        }
    }

    // MARK: Pieces

    private func searchField(placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(RCMenuInk.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .onKeyPress(.escape) { close(); return .handled }
                .accessibilityLabel(placeholder)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .foregroundStyle(RCMenuInk.dim)
        .padding(.leading, 10)
        .frame(minHeight: 40)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(RCMenuInk.separator, lineWidth: 1))
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.footnote.weight(.medium))
            .tracking(1.2)
            .foregroundStyle(RCMenuInk.dim)
            .padding(.horizontal, RCMenuInk.gutter)
            .padding(.top, 14)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(RCMenuInk.separator).frame(height: 1) }
            .accessibilityAddTraits(.isHeader)
    }

    private func emptyMessage(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).foregroundStyle(RCMenuInk.text).fontWeight(.semibold)
            Text(detail).foregroundStyle(RCMenuInk.dim)
        }
        .font(.subheadline)
        .padding(.horizontal, RCMenuInk.gutter)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func navigate(_ next: RCMenuPage) {
        searchFocused = false
        if next == .samples { refreshSamples?() }
        page = next
        titleFocused = true
    }

    private func matchesPreset(_ index: Int) -> Bool {
        guard Preset.factory.indices.contains(index) else { return false }
        let preset = Preset.factory[index]
        return Param.allCases.filter { $0 != .bypass }.allSatisfy { parameter in
            let expected = preset.values[parameter] ?? parameter.defaultValue
            return abs(params[parameter] - expected) < 0.0001
        }
    }
}

// MARK: - Parallel mixer

/// The parallel mixer: LINKED is the classic Mix crossfade, UNLINKED gives Dry and Wet their own
/// levels.
@MainActor
private struct RCMixerPage: View {
    @ObservedObject var params: ParamStore

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(knob: 112, caption: true)
            content(knob: 84, caption: false)
            content(knob: 64, caption: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func content(knob: CGFloat, caption: Bool) -> some View {
        let unlinked = params.mixUnlinked
        return VStack(spacing: 12) {
            HStack(spacing: 6) {
                modeButton("LINKED", detail: "ONE MIX KNOB", on: !unlinked) { params[.mixUnlink] = 0 }
                modeButton("UNLINKED", detail: "DRY + WET", on: unlinked) { params[.mixUnlink] = 1 }
            }
            HStack(alignment: .top, spacing: 18) {
                Knob(title: "Dry", value: params.mixerBinding(wet: false), range: 0...100,
                     defaultValue: unlinked ? Param.dry.defaultValue : 100 - Param.mix.defaultValue,
                     diameter: knob, minLabel: "0", maxLabel: "100", format: Fmt.pct)
                    .accessibilityLabel("Dry level")
                Knob(title: "Wet", value: params.mixerBinding(wet: true), range: 0...100,
                     defaultValue: unlinked ? Param.wet.defaultValue : Param.mix.defaultValue,
                     diameter: knob, minLabel: "0", maxLabel: "100", format: Fmt.pct)
                    .accessibilityLabel("Wet level")
            }
            if caption {
                Text(unlinked
                     ? "Dry and Wet move on their own. Try 100 % Dry under a heavily driven Wet for bottom-up distortion, or clip gently and blend Dry back for peaks."
                     : "Mix crossfades: more Wet means less Dry. Unlink to set them separately.")
                    .font(.footnote)
                    .foregroundStyle(RCMenuInk.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }

    private func modeButton(_ title: String, detail: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(on ? Color.black : RCMenuInk.text)
                Text(detail)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(on ? Color.black.opacity(0.7) : RCMenuInk.dim)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? RCMenuInk.accent : RCMenuInk.raised))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? RCMenuInk.accent : RCMenuInk.separator, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

// MARK: - Header

private struct RCMenuHeader: View {
    let page: RCMenuPage
    let platinum: Bool
    var titleFocused: AccessibilityFocusState<Bool>.Binding
    let back: () -> Void
    let close: () -> Void
    @ScaledMetric(relativeTo: .headline) private var brandSize: CGFloat = 17

    private var ink: Color { platinum ? Color(white: 0.13) : RCMenuInk.text }
    private var emboss: Color { platinum ? Color.white.opacity(0.75) : Color.black.opacity(0.55) }

    var body: some View {
        HStack(spacing: 8) {
            if page == .home {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("REDCLIP")
                        .font(.system(size: brandSize, weight: .semibold))
                        .tracking(brandSize * 0.32)
                    Text("MENU")
                        .font(.system(size: brandSize * 0.68, weight: .medium))
                        .tracking(brandSize * 0.12)
                        .opacity(0.8)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.leading, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("RedClip menu")
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocused)
            } else {
                RCMenuMetalKey(systemName: "chevron.left", platinum: platinum, action: back)
                    .accessibilityLabel("Back")
                Text(page.title)
                    .font(.system(size: brandSize * 0.95, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(titleFocused)
            }
            Spacer(minLength: 4)
            RCMenuMetalKey(systemName: "xmark", platinum: platinum, action: close)
                .accessibilityLabel("Close menu")
                .keyboardShortcut(.escape, modifiers: [])
        }
        .foregroundStyle(ink)
        .shadow(color: emboss, radius: 0, x: 0, y: 1)
        .padding(.horizontal, 6)
        .frame(minHeight: RCMenuInk.headerHeight)
    }
}

/// A small square key inset into the metal header, 44 × 44 touch area.
private struct RCMenuMetalKey: View {
    let systemName: String
    let platinum: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(RCMenuKeyStyle(platinum: platinum))
    }
}

private struct RCMenuKeyStyle: ButtonStyle {
    let platinum: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(
                        colors: platinum
                            ? [Color(white: pressed ? 0.72 : 0.93), Color(white: pressed ? 0.62 : 0.74)]
                            : [Color(red: 0.42, green: 0.06, blue: 0.07), Color(red: 0.22, green: 0.02, blue: 0.03)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.55), lineWidth: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(pressed ? 0.1 : (platinum ? 0.8 : 0.25)), lineWidth: 1)
                            .padding(1)
                    }
                    .frame(width: 34, height: 34)
            }
            .offset(y: pressed ? 0.5 : 0)
    }
}

// MARK: - Rows

private struct RCMenuRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var number: Int? = nil
    var selected = false
    var detail: String? = nil
    var chevron = false
    var separator = true
    var hint: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 26

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let number {
                    Text(String(format: "%03d", number))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(selected ? RCMenuInk.accent : RCMenuInk.dim)
                        .frame(minWidth: iconWidth, alignment: .leading)
                        .accessibilityHidden(true)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(RCMenuInk.text)
                        .frame(width: iconWidth)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(RCMenuInk.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(RCMenuInk.dim)
                    }
                }
                Spacer(minLength: 4)
                if let detail {
                    Text(detail.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(RCMenuInk.dim)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(RCMenuInk.text)
                        .accessibilityHidden(true)
                } else if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RCMenuInk.text.opacity(0.85))
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, RCMenuInk.gutter)
            .padding(.trailing, RCMenuInk.gutter - 2)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: RCMenuInk.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RCMenuRowStyle(selected: selected))
        .opacity(isEnabled ? 1 : 0.4)
        .overlay(alignment: .bottom) {
            if separator {
                Rectangle().fill(RCMenuInk.separator).frame(height: 1)
                    .padding(.leading, RCMenuInk.gutter)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityValue(selected ? (detail.map { "Selected, \($0)" } ?? "Selected") : "")
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Flush row: burgundy fill and a red edge when selected; a raised dark fill and the same edge
/// while pressed. Selection also has a checkmark, so red is never the only signal.
private struct RCMenuRowStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background {
                ZStack(alignment: .leading) {
                    if selected {
                        RCMenuInk.selection
                    } else if pressed {
                        RCMenuInk.raised
                    }
                    if selected || pressed {
                        Rectangle().fill(RCMenuInk.accent).frame(width: 4)
                    }
                }
                .overlay(alignment: .top) {
                    // Subtle depth: a faint top highlight on lit rows.
                    if selected || pressed {
                        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                    }
                }
            }
    }
}

// MARK: - Metal

/// Satin brushed metal: a vertical light falloff plus fixed horizontal grain. The grain is drawn
/// once into an offscreen layer (drawingGroup); nothing animates or redraws per frame.
private struct RCMenuMetal: View {
    let platinum: Bool

    var body: some View {
        let stops: [Gradient.Stop] = platinum
            ? [Gradient.Stop(color: Color(red: 0.89, green: 0.886, blue: 0.875), location: 0),
               Gradient.Stop(color: Color(red: 0.80, green: 0.796, blue: 0.788), location: 0.08),
               Gradient.Stop(color: Color(red: 0.70, green: 0.698, blue: 0.69), location: 0.55),
               Gradient.Stop(color: Color(red: 0.573, green: 0.573, blue: 0.565), location: 1)]
            : [Gradient.Stop(color: Color(red: 0.66, green: 0.12, blue: 0.13), location: 0),
               Gradient.Stop(color: Color(red: 0.55, green: 0.07, blue: 0.08), location: 0.08),
               Gradient.Stop(color: Color(red: 0.42, green: 0.04, blue: 0.05), location: 0.55),
               Gradient.Stop(color: Color(red: 0.30, green: 0.02, blue: 0.03), location: 1)]
        ZStack {
            LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                var seed: UInt64 = 0x5EED_C11F
                var y: CGFloat = 0
                while y < size.height {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let r = Double((seed >> 33) % 1000) / 1000
                    let light = r > 0.5
                    let alpha = (light ? r - 0.5 : 0.5 - r) * (platinum ? 0.16 : 0.12)
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)),
                                 with: .color(light ? Color.white.opacity(alpha) : Color.black.opacity(alpha)))
                    y += 0.9
                }
            }
            .allowsHitTesting(false)
        }
        .drawingGroup()
    }
}
