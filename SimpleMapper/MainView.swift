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
                Button(action: newMapping) { Label("New mapping", systemImage: "plus") }
                    .help("New mapping")
            }
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

    @ViewBuilder private var mappingList: some View {
        let list = model.settings.list(for: current)
        VStack(alignment: .leading, spacing: 8) {
            let inherited = Settings.dedupe(model.settings.all).count
            if current != .all && inherited > 0 {
                Text("Also uses \(inherited) \(inherited == 1 ? "mapping" : "mappings") from All keyboards; the same From key here wins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            if list.isEmpty {
                Text("No mappings yet. Click + to add one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                GlassCards {
                    VStack(spacing: 8) {
                        ForEach(list) { row($0) }
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

    private func row(_ mapping: Mapping) -> some View {
        HStack(spacing: 8) {
            KeyMenu(usage: mapping.from, tint: .from) { model.setFrom($0, for: mapping.id, in: current) }
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            KeyMenu(usage: mapping.to, tint: .to) { model.setTo($0, for: mapping.id, in: current) }
            Spacer(minLength: 8)
            Toggle("Enabled", isOn: Binding(
                get: { mapping.enabled },
                set: { model.setEnabled($0, for: mapping.id, in: current) }
            ))
            .toggleStyle(CompactSwitch())
            Button { model.remove(mapping.id, in: current) } label: {
                Label("Remove", systemImage: "trash").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(GlassCard(cornerRadius: 20))
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

    static func label(_ usage: UInt64) -> String {
        KeyCatalog.key(usage: usage)?.label ?? String(format: "0x%llX", usage)
    }

    var body: some View {
        Menu {
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

/// A small on/off switch; the system switch stays wide even at `.mini` on macOS 26.
struct CompactSwitch: ToggleStyle {
    private static let offFill = Color(light: .black.withAlphaComponent(0.18), dark: .white.withAlphaComponent(0.22))

    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(configuration.isOn ? Color.accentColor : Self.offFill)
            .frame(width: 26, height: 15)
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
