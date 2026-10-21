// Red Clip — custom MS26-style preset and audio browser.
// Requires the existing Red Clip types; not a standalone app.
// iOS 17+, SwiftUI. Opened from the preset name (Faceplate.swift) and the app's Samples key
// (AppRootView.swift); hosted once per root, outside the scaled faceplate, by redClipPresetMenuHost.
import SwiftUI

enum RCMenuAnchor: Hashable { case presets, samples }

enum RCMenuPage: Equatable {
    case home
    case bank(String)
    case samples
    case faceplates

    var title: String {
        switch self {
        case .home: return "PRESET MEMORY"
        case .bank(let name): return name.uppercased()
        case .samples: return "SAMPLES"
        case .faceplates: return "FACEPLATE"
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
    func rcMenuAnchor(_ anchor: RCMenuAnchor) -> some View {
        anchorPreference(key: RCMenuAnchorKey.self, value: .bounds) { [anchor: $0] }
    }

    /// Install AFTER the faceplate's scaleEffect and final host-sized frame.
    @MainActor
    func redClipPresetMenuHost(face: FaceModel,
                               refreshSamples: (() -> Void)? = nil) -> some View {
        modifier(RCMenuHost(face: face, refreshSamples: refreshSamples))
    }
}

@MainActor
private struct RCMenuHost: ViewModifier {
    @ObservedObject var face: FaceModel
    var refreshSamples: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                                                         anchor: trigger)
                        ZStack(alignment: .topLeading) {
                            // Invisible outside-tap catcher. It consumes the dismissal tap
                            // so a control underneath cannot turn on accidentally.
                            Color.black.opacity(0.001)
                                .contentShape(Rectangle())
                                .onTapGesture { face.rcMenuRequest = nil }
                                .accessibilityHidden(true)

                            RCMenuPanel(face: face, params: face.params,
                                        initialPage: request.page,
                                        refreshSamples: refreshSamples,
                                        close: { face.rcMenuRequest = nil })
                                .id(request.id)
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .transition(.opacity)
                        .zIndex(100)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14),
                       value: face.rcMenuRequest != nil)
            .onDisappear { face.rcMenuRequest = nil }
    }
}

/// Everything is measured in the actual host's points, never UIScreen bounds.
/// Recomputes for rotation, keyboard avoidance, split view and AUv3 window resizing.
enum RCMenuPlacement {
    static func frame(size: CGSize, safe: EdgeInsets, anchor: CGRect) -> CGRect {
        let margin: CGFloat = 12
        let left = min(size.width, max(0, safe.leading) + margin)
        let top = min(size.height, max(0, safe.top) + margin)
        let right = max(left, size.width - max(0, safe.trailing) - margin)
        let bottom = max(top, size.height - max(0, safe.bottom) - margin)
        let width = min(352, max(0, right - left))
        let availableHeight = max(0, bottom - top)
        let height = min(availableHeight, max(256, min(600, availableHeight * 0.72)))
        let x = min(max(anchor.midX - width / 2, left), max(left, right - width))
        let below = bottom - anchor.maxY - 8
        let above = anchor.minY - top - 8
        let preferredY: CGFloat
        if below >= height {
            preferredY = anchor.maxY + 8
        } else if above >= height {
            preferredY = anchor.minY - height - 8
        } else {
            preferredY = below >= above ? anchor.maxY + 8 : anchor.minY - height - 8
        }
        let y = min(max(preferredY, top), max(top, bottom - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private enum RCMenuInk {
    static let accent = Color(red: 1, green: 0.27, blue: 0.27)
    static let background = Color(red: 0.035, green: 0.032, blue: 0.029)
    static let raised = Color(white: 0.105)
    static let text = Color(white: 0.94)
    static let dim = Color(white: 0.67)
    static let line = Color(white: 0.25)
}

@MainActor
private struct RCMenuPanel: View {
    @ObservedObject var face: FaceModel
    @ObservedObject var params: ParamStore
    let refreshSamples: (() -> Void)?
    let close: () -> Void
    @State private var page: RCMenuPage
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool
    @ScaledMetric(relativeTo: .headline) private var headingSize: CGFloat = 15

    init(face: FaceModel, params: ParamStore, initialPage: RCMenuPage,
         refreshSamples: (() -> Void)?, close: @escaping () -> Void) {
        self.face = face
        self.params = params
        self.refreshSamples = refreshSamples
        self.close = close
        _page = State(initialValue: initialPage)
    }

    private var platinum: Bool { face.faceplate == .face1Platinum }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showingSearch: Bool { page != .faceplates }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(RCMenuInk.accent.opacity(0.65)).frame(height: 1)
            if showingSearch { searchField }
            if page != .home { backBar }
            browser
            footer
        }
        .background(RCMenuInk.background)
        .padding(3)
        .background {
            RCMenuMetal(platinum: platinum)
                .contentShape(Rectangle())
                .onTapGesture { searchFocused = false }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.white.opacity(platinum ? 0.65 : 0.2), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.65), radius: 13, x: 0, y: 9)
        .preferredColorScheme(.dark)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear { titleFocused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text("RED CLIP")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(2)
                    .opacity(0.68)
                Text("PRESET MEMORY")
                    .font(.system(size: headingSize, weight: .black, design: .monospaced))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close preset menu")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .foregroundStyle(platinum ? Color(white: 0.10) : Color(white: 0.95))
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .frame(minHeight: 54)
        .background(RCMenuMetal(platinum: platinum))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField(page == .samples ? "SEARCH SAMPLES" : "SEARCH PRESETS", text: $search)
                .textFieldStyle(.plain)
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .foregroundStyle(RCMenuInk.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .onKeyPress(.escape) { close(); return .handled }
                .accessibilityLabel(page == .samples ? "Search samples" : "Search presets")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .foregroundStyle(RCMenuInk.dim)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
        .background(Color.black.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(RCMenuInk.line).frame(height: 1)
        }
    }

    private var backBar: some View {
        HStack(spacing: 8) {
            Button { navigate(.home) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to categories")
            Text(page.title)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if page == .samples, let refreshSamples {
                Button(action: refreshSamples) {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh samples")
            }
        }
        .foregroundStyle(RCMenuInk.accent)
        .padding(.trailing, 8)
        .background(Color.black.opacity(0.26))
    }

    private var browser: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    pageContents
                }
                .padding(10)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(page.title)
            .onChange(of: page) { _, value in
                if case .bank(let bank) = value,
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

    @ViewBuilder
    private var pageContents: some View {
        switch page {
        case .home:
            if query.isEmpty {
                homeContents
            } else {
                sectionTitle("ALL PRESETS")
                presetRows(bank: nil)
            }
        case .bank(let bank):
            presetRows(bank: bank)
        case .samples:
            sampleRows
        case .faceplates:
            ForEach(Faceplate.allCases, id: \.self) { finish in
                RCMenuRow(title: finish.title, icon: "paintbrush",
                          selected: face.faceplate == finish,
                          detail: face.faceplate == finish ? "SELECTED" : nil) {
                    face.faceplate = finish
                }
            }
        }
    }

    @ViewBuilder
    private var homeContents: some View {
        if !face.isPlugin {
            sectionTitle("AUDIO")
            RCMenuRow(title: "Import Audio from Files…", icon: "square.and.arrow.down") {
                close()
                // Keep the app's existing system file-access picker and loader.
                face.importRequested = true
            }
            RCMenuRow(title: "Samples", icon: "square.stack.3d.down.right",
                      detail: "\(face.sampleFiles.count)", chevron: true) {
                navigate(.samples)
            }
            RCMenuRow(title: "Demo Loop", icon: "music.note") {
                face.loadDemo?()
            }
            .disabled(face.loadDemo == nil)
            .opacity(face.loadDemo == nil ? 0.45 : 1)
        }
        sectionTitle("PRESETS")
        ForEach(Preset.banks, id: \.self) { bank in
            RCMenuRow(title: bank, icon: "square.grid.2x2",
                      detail: "\(Preset.factory.filter { $0.bank == bank }.count)",
                      chevron: true) {
                navigate(.bank(bank))
            }
        }
        sectionTitle("SETTINGS")
        RCMenuRow(title: "Faceplate", icon: "paintbrush", chevron: true) {
            navigate(.faceplates)
        }
    }

    @ViewBuilder
    private func presetRows(bank: String?) -> some View {
        let indices = Preset.factory.indices.filter { index in
            let item = Preset.factory[index]
            return (bank == nil || item.bank == bank)
                && (query.isEmpty || item.name.localizedStandardContains(query)
                    || item.bank.localizedStandardContains(query))
        }
        if indices.isEmpty {
            emptyMessage("NO MATCHING PRESETS", detail: "Try a name or category.")
        } else {
            ForEach(indices, id: \.self) { index in
                let item = Preset.factory[index]
                let selected = params.presetIndex == index
                RCMenuRow(title: item.name, subtitle: bank == nil ? item.bank : nil,
                          number: index + 1, selected: selected,
                          detail: selected ? (matchesPreset(index) ? "LOADED" : "EDITED") : nil) {
                    // Use the app's real undo + parameter + AU notification path once.
                    // No local preset copies, fake DSP, engine stop, or restart.
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
            emptyMessage("HOST AUDIO", detail: "The host supplies audio in AUv3.")
        } else {
            let items = face.sampleFiles.filter {
                query.isEmpty || $0.name.localizedStandardContains(query)
            }
            if items.isEmpty {
                emptyMessage(query.isEmpty ? "NO SAMPLES YET" : "NO MATCHING SAMPLES",
                             detail: query.isEmpty ? "Import audio from Files to add a sample." : "Try another filename.")
                if query.isEmpty {
                    RCMenuRow(title: "Import Audio from Files…", icon: "square.and.arrow.down") {
                        close()
                        face.importRequested = true
                    }
                }
            } else {
                ForEach(items) { item in
                    RCMenuRow(title: item.name, icon: "waveform") {
                        face.loadSample?(item.url)
                        searchFocused = false
                    }
                    .disabled(face.loadSample == nil)
                    .opacity(face.loadSample == nil ? 0.45 : 1)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TAP TO LOAD • MENU STAYS OPEN")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(RCMenuInk.dim)
            Text("LAST PRESET: \(params.presetName)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(RCMenuInk.accent)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.4))
        .overlay(alignment: .top) { Rectangle().fill(RCMenuInk.line).frame(height: 1) }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced, weight: .black))
            .tracking(1.8)
            .foregroundStyle(RCMenuInk.dim)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }

    private func emptyMessage(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(RCMenuInk.accent).fontWeight(.bold)
            Text(detail).foregroundStyle(RCMenuInk.dim)
        }
        .font(.system(.subheadline, design: .monospaced))
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func navigate(_ next: RCMenuPage) {
        searchFocused = false
        search = ""
        page = next
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

private struct RCMenuRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var number: Int? = nil
    var selected = false
    var detail: String? = nil
    var chevron = false
    let action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var fontSize: CGFloat = 14

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let number {
                    Text(String(format: "%03d", number))
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(selected ? Color.black : RCMenuInk.accent)
                        .frame(width: 34, height: 24)
                        .background(selected ? RCMenuInk.accent : Color.black.opacity(0.6))
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? RCMenuInk.accent : RCMenuInk.dim)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(RCMenuInk.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle.uppercased())
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(RCMenuInk.dim)
                    }
                    if let detail, selected {
                        Text(detail)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(RCMenuInk.accent)
                    }
                }
                Spacer(minLength: 0)
                if let detail, !selected {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(RCMenuInk.dim)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(RCMenuInk.accent)
                } else if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RCMenuInk.dim)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background {
                LinearGradient(colors: [Color(white: selected ? 0.15 : 0.105), Color(white: 0.055)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                Rectangle().strokeBorder(selected ? RCMenuInk.accent : RCMenuInk.line,
                                         lineWidth: selected ? 1.5 : 1)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.horizontal, 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RCMenuPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityValue(selected ? (detail ?? "Selected") : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct RCMenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Color.black.opacity(configuration.isPressed ? 0.18 : 0).allowsHitTesting(false))
            .offset(y: configuration.isPressed ? 0.5 : 0)
    }
}

private struct RCMenuMetal: View {
    let platinum: Bool
    var body: some View {
        LinearGradient(
            colors: platinum
                ? [Color(white: 0.88), Color(white: 0.58), Color(white: 0.79), Color(white: 0.46)]
                : [Color(red: 0.56, green: 0.09, blue: 0.09),
                   Color(red: 0.25, green: 0.025, blue: 0.025),
                   Color(red: 0.46, green: 0.055, blue: 0.055)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
