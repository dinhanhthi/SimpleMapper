import SwiftUI
import UniformTypeIdentifiers

/// The main window: the mapping list of one keyboard scope, with the keyboard picker, the theme button,
/// import/export and "+" (New mapping) in the toolbar.
struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: KeyboardMonitor
    @ObservedObject var detector: KeyDetector
    /// Shows the New mapping window.
    let onNewMapping: (NewMappingView) -> Void
    @StateObject private var selection = KeyboardSelection()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            mappingList.padding(12)
        }
        .background(WindowGlass().ignoresSafeArea())
        .frame(minWidth: 440, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                // A menu-style Picker fills the toolbar; a Menu sizes to the picked keyboard's name.
                Menu {
                    Picker("Keyboard", selection: pickedScope) {
                        Text("All keyboards").tag(Scope.all)
                        ForEach(monitor.devices) { device in
                            Text(device.name).tag(device.scope)
                        }
                        ForEach(savedOnly, id: \.id) { device in
                            Text("\(device.name) (not connected)").tag(device.scope)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Text(device(for: current)?.name ?? "All keyboards")
                        .padding(.horizontal, 8)
                }
                .help("Keyboard")
            }
            // Pushes the buttons to the trailing edge.
            if #available(macOS 26, *) {
                ToolbarSpacer(.flexible)
            } else {
                ToolbarItem { Spacer() }
            }
            ToolbarItemGroup {
                Button { Theme.set(dark: colorScheme != .dark) } label: {
                    Label(colorScheme == .dark ? "Light mode" : "Dark mode",
                          systemImage: colorScheme == .dark ? "sun.max" : "moon")
                }
                .help(colorScheme == .dark ? "Switch to Light mode" : "Switch to Dark mode")
                Button(action: importSettings) { Label("Import…", systemImage: "square.and.arrow.down") }
                    .help("Import settings")
                Button(action: exportSettings) { Label("Export…", systemImage: "square.and.arrow.up") }
                    .help("Export settings")
            }
            // In a narrow window the other buttons go to the overflow menu first.
            if #available(macOS 26.1, *) {
                newMappingItem.visibilityPriority(.high)
            } else {
                newMappingItem
            }
        }
    }

    private var newMappingItem: some ToolbarContent {
        ToolbarItem {
            Button(action: newMapping) { Label("New mapping", systemImage: "plus") }
                .help("New mapping")
        }
    }

    // MARK: Scope

    /// Saved keyboards that are not connected.
    private var savedOnly: [KeyboardDevice] {
        model.settings.keyboards.map(\.device).filter { saved in !monitor.devices.contains { $0.scope == saved.scope } }
    }

    /// The picked keyboard; "All keyboards" once it is neither connected nor saved any more.
    private var current: Scope {
        device(for: selection.scope) == nil ? .all : selection.scope
    }

    private var pickedScope: Binding<Scope> {
        Binding(get: { current }, set: { selection.scope = $0 })
    }

    /// The connected keyboard for `scope`, else the saved one; `nil` for `.all`.
    private func device(for scope: Scope) -> KeyboardDevice? {
        guard scope != .all else { return nil }
        return monitor.devices.first { $0.scope == scope } ?? savedOnly.first { $0.scope == scope }
    }

    // MARK: Mappings

    /// The list for `current`. For a keyboard: the All list without its excluded keys, each row replaced by the
    /// keyboard's own row with the same From key (else marked inherited), then the keyboard's other rows.
    private var shownRows: [(mapping: Mapping, inherited: Bool)] {
        let own = model.settings.list(for: current)
        guard current != .all else { return own.map { ($0, false) } }
        let excluded = Set(model.settings.excluded(for: current))
        var rows: [(mapping: Mapping, inherited: Bool)] = []
        var froms = Set<UInt64>()
        for mapping in model.settings.all where froms.insert(mapping.from).inserted {
            if let mine = own.first(where: { $0.from == mapping.from }) {
                rows.append((mine, false))
            } else if !excluded.contains(mapping.from), let followed = model.settings.allMapping(from: mapping.from) {
                rows.append((followed, true))
            }
        }
        return rows + own.filter { mine in !rows.contains { $0.mapping.id == mine.id } }.map { ($0, false) }
    }

    @ViewBuilder private var mappingList: some View {
        let rows = shownRows
        VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text("No mappings yet. Click + to add one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                GlassCards {
                    VStack(spacing: 14) {
                        ForEach(rows, id: \.mapping.id) { row($0.mapping, inherited: $0.inherited) }
                    }
                }
            }
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// An inherited row is an All row shown for a keyboard; changing its From, To or switch gives the keyboard its
    /// own copy, which later All changes no longer affect. For a keyboard, a row whose From key the All list maps
    /// has a dot: green when its To and switch equal the All mapping, else gray (a click takes the All values).
    private func row(_ mapping: Mapping, inherited: Bool) -> some View {
        let followed = current == .all ? nil : model.settings.allMapping(from: mapping.from)
        let sameAsAll = followed.map { $0.to == mapping.to && $0.enabled == mapping.enabled } ?? false
        return HStack(spacing: 8) {
            KeyMenu(usage: mapping.from, tint: .from) { model.setFrom($0, for: mapping, in: device(for: current)) }
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            KeyMenu(usage: mapping.to, tint: .to) { to in
                if inherited {
                    model.override(from: mapping.from, to: to, enabled: mapping.enabled, in: device(for: current))
                } else {
                    model.setTo(to, for: mapping.id, in: current)
                }
            }
            Spacer(minLength: 8)
            if followed != nil {
                // Not disabled while green, so its tooltip still shows.
                Button { if !sameAsAll { model.useAll(mapping.from, in: current) } } label: {
                    Circle()
                        .fill(sameAsAll ? Color.green : CompactSwitch.offFill)
                        .frame(width: CompactSwitch.height, height: CompactSwitch.height)
                }
                .buttonStyle(RowIconButtonStyle())
                .help(sameAsAll ? "From All keyboards: ON" : "From All keyboards: OFF (click to use All keyboards)")
            }
            if current == .all {
                Button { confirmApplyToAllKeyboards(mapping) } label: {
                    Label("Apply to every keyboard", systemImage: "square.stack.3d.down.forward")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 15))
                        .frame(height: CompactSwitch.height)
                }
                .buttonStyle(RowIconButtonStyle())
                .foregroundStyle(.secondary)
                .help("Apply to every keyboard")
            }
            Toggle("Enabled", isOn: Binding(
                get: { mapping.enabled },
                set: { enabled in
                    if inherited {
                        model.override(from: mapping.from, to: mapping.to, enabled: enabled, in: device(for: current))
                    } else {
                        model.setEnabled(enabled, for: mapping.id, in: current)
                    }
                }
            ))
            .toggleStyle(CompactSwitch())
            Button { confirmRemove(mapping) } label: {
                Label("Remove", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15))
                    .frame(height: CompactSwitch.height)
            }
            .buttonStyle(RowIconButtonStyle())
            .foregroundStyle(.secondary)
            .help("Remove")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(GlassCard(cornerRadius: 20))
    }

    /// Asks first. For a keyboard, a key the All list maps is excluded there, so its All mapping is not used either.
    /// Asks first, naming the keyboards that use their own mapping for this key or removed it.
    private func confirmApplyToAllKeyboards(_ mapping: Mapping) {
        let names = model.settings.keyboardsNotFollowingAll(mapping.from).map(\.name)
        let alert = NSAlert()
        alert.messageText = "Apply \(KeyMenu.label(mapping.from)) → \(KeyMenu.label(mapping.to)) to every keyboard?"
        alert.informativeText = names.isEmpty
            ? "Every keyboard already uses it."
            : "These keyboards drop their own mapping for this key and use this one: \(names.joined(separator: ", "))."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.applyToAllKeyboards(mapping.from)
    }

    private func confirmRemove(_ mapping: Mapping) {
        let alert = NSAlert()
        alert.messageText = "Remove \(KeyMenu.label(mapping.from)) → \(KeyMenu.label(mapping.to))?"
        alert.informativeText = current == .all
            ? "It is removed from All keyboards."
            : "It is removed from this keyboard only. Click + to add it again."
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let device = device(for: current), model.settings.allMapping(from: mapping.from) != nil {
            model.exclude(mapping.from, in: device)
        } else {
            model.remove(mapping.id, in: current)
        }
    }

    private func newMapping() {
        onNewMapping(NewMappingView(model: model, detector: detector, selection: selection) { from, to in
            model.add(from: from, to: to, in: device(for: current))
        })
    }

    // MARK: Import / export

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.importSettings(from: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SimpleMapper-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportSettings(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// The Light or Dark choice of the toolbar's theme button, kept in UserDefaults; until it is used, the app
/// follows the system appearance.
enum Theme {
    private static let key = "Theme"

    /// Applies the saved choice; called at launch.
    static func applySaved() {
        guard let name = UserDefaults.standard.string(forKey: key) else { return }
        NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
    }

    static func set(dark: Bool) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        UserDefaults.standard.set(dark ? "dark" : "light", forKey: key)
    }
}

/// Which keyboard's list the main window shows; shared with the New mapping window.
@MainActor
final class KeyboardSelection: ObservableObject {
    @Published var scope: Scope = .all
}

/// A key-cap button opening the key catalog by category, with a checkmark on the current key. A long key name
/// ends with an ellipsis instead of widening the row.
struct KeyMenu: View {
    let usage: UInt64?
    /// The gradient behind a chosen key; "Choose key…" stays plain.
    var tint: KeyCap.Tint = .plain
    let onSelect: (UInt64) -> Void
    @State private var detecting = false

    static func label(_ usage: UInt64) -> String {
        KeyCatalog.key(usage: usage)?.label ?? String(format: "0x%llX", usage)
    }

    var body: some View {
        Menu {
            Button("Detect auto…") { detecting = true }
            Divider()
            ForEach(Category.allCases, id: \.self) { category in
                Menu(category.title) {
                    ForEach(KeyCatalog.all.filter { $0.category == category }) { key in
                        Toggle(key.label, isOn: Binding(
                            get: { usage.flatMap { KeyCatalog.key(usage: $0)?.name } == key.name },
                            set: { if $0 { onSelect(key.usage) } }
                        ))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(usage.map(Self.label) ?? "Choose key…")
                    .font(usage == nil ? .body : .system(.body, design: .monospaced).weight(.medium))
                    .foregroundStyle(usage == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .modifier(KeyCap(tint: usage == nil ? .plain : tint))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $detecting) { DetectKeyView(onUse: onSelect) }
    }
}

/// The sheet of "Detect auto…": detects one key press as soon as it opens, with "Use it", Grant Access and Cancel.
/// It has its own detector, so the New mapping window's Detect key row stays untouched.
struct DetectKeyView: View {
    let onUse: (UInt64) -> Void
    @StateObject private var detector = KeyDetector()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Detect key").font(.headline)
            if detector.isDetecting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Press any key…")
                }
            } else if let detected = detector.detected {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detected.key?.label ?? KeyMenu.label(detected.usage))
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .modifier(KeyCap())
                    HStack(spacing: 6) {
                        if let key = detected.key {
                            Text(key.name)
                                .font(.system(.caption, design: .monospaced))
                            Text("·")
                        }
                        Text(detected.device?.name ?? "Unknown keyboard")
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if detector.permissionDenied && !detector.isDetecting {
                Text("Input Monitoring access is needed to detect keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Grant Access…") { detector.requestAccess() }
                    .controlSize(.small)
            }
            if let hint = detector.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if !detector.isDetecting {
                    // After the 10 s timeout, a miss or a grant in System Settings.
                    Button("Detect again") { detector.start() }
                }
                Spacer()
                // Keys are swallowed while detecting, so Escape only cancels once detection stops.
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use it") {
                    guard let usage = detector.detected?.usage else { return }
                    onUse(usage)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(detector.detected == nil)
            }
            .buttonBorderShape(.capsule)
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { detector.start() }
        .onDisappear { detector.stop() }
    }
}

/// The inline box behind a key label: padding and its own rounded background, plain (darker than the glass row)
/// or the poster's blue-violet (From) and lilac-cyan (To) gradients, deeper and translucent in Dark mode.
struct KeyCap: ViewModifier {
    enum Tint { case plain, from, to }

    var tint: Tint = .plain

    private static let fill = Color(light: .black.withAlphaComponent(0.08), dark: .black.withAlphaComponent(0.35))
    private static let from = [
        Color(light: NSColor(hex: 0xCFD9FD), dark: NSColor(hex: 0x7191F8, alpha: 0.45)),
        Color(light: NSColor(hex: 0xDFCFFC), dark: NSColor(hex: 0xAD85F6, alpha: 0.45)),
    ]
    private static let to = [
        Color(light: NSColor(hex: 0xEFDCFD), dark: NSColor(hex: 0xB48CF0, alpha: 0.42)),
        Color(light: NSColor(hex: 0xD2F3FB), dark: NSColor(hex: 0x5EC8E6, alpha: 0.38)),
    ]
    // Light mode only: there a pale cap is close to the white glass row.
    private static let plainBorder = Color(light: .black.withAlphaComponent(0.14), dark: .clear)
    private static let fromBorder = Color(light: NSColor(hex: 0x9C8AF0, alpha: 0.5), dark: .clear)
    private static let toBorder = Color(light: NSColor(hex: 0x6FC3DC, alpha: 0.55), dark: .clear)

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(background, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(border, lineWidth: 1))
    }

    private var border: Color {
        switch tint {
        case .plain: return Self.plainBorder
        case .from: return Self.fromBorder
        case .to: return Self.toBorder
        }
    }

    private var background: AnyShapeStyle {
        switch tint {
        case .plain: return AnyShapeStyle(Self.fill)
        case .from: return AnyShapeStyle(LinearGradient(colors: Self.from, startPoint: .topLeading, endPoint: .bottomTrailing))
        case .to: return AnyShapeStyle(LinearGradient(colors: Self.to, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

/// The icon buttons of a row (dot, Apply to every keyboard, Remove): a round highlight on hover, darker and a bit
/// smaller while pressed. The highlight reaches past the label without changing the row's layout.
struct RowIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Highlight(configuration: configuration)
    }

    private struct Highlight: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        private static let hoverFill = Color(light: .black.withAlphaComponent(0.07), dark: .white.withAlphaComponent(0.1))
        private static let pressedFill = Color(light: .black.withAlphaComponent(0.15), dark: .white.withAlphaComponent(0.2))

        var body: some View {
            configuration.label
                .background {
                    Circle()
                        .fill(configuration.isPressed ? Self.pressedFill : hovered ? Self.hoverFill : .clear)
                        .padding(-5)
                }
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.88 : 1)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

/// A small on/off switch; the system switch stays wide even at `.mini` on macOS 26.
struct CompactSwitch: ToggleStyle {
    static let height: CGFloat = 19
    static let offFill = Color(light: .black.withAlphaComponent(0.18), dark: .white.withAlphaComponent(0.22))

    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(configuration.isOn ? Color.accentColor : Self.offFill)
            .frame(width: 34, height: Self.height)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                    .padding(1.5)
            }
            .animation(.snappy(duration: 0.2), value: configuration.isOn)
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
    }
}

/// The translucent window background, blurring what is behind the window (toolbar included).
struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension NSColor {
    /// An sRGB color from `0xRRGGBB`.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// A color with one value for Light and one for Dark appearance.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// Liquid Glass on macOS 26+, a material card before.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Groups glass cards in a `GlassEffectContainer` on macOS 26+.
struct GlassCards<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}
