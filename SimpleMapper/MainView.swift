import SwiftUI
import UniformTypeIdentifiers

/// The main window: the mapping list of one keyboard scope, a "New mapping" box and import/export.
struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: KeyboardMonitor
    @ObservedObject var detector: KeyDetector
    @State private var scope: Scope = .all
    @State private var newFrom: UInt64?
    @State private var newTo: UInt64?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Keyboard", selection: selection) {
                Text("All keyboards").tag(Scope.all)
                ForEach(monitor.devices) { device in
                    Text(device.name).tag(device.scope)
                }
                ForEach(savedOnly, id: \.id) { device in
                    Text("\(device.name) (not connected)").tag(device.scope)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            GlassCards {
                VStack(alignment: .leading, spacing: 16) {
                    mappingList
                    newMappingCard
                    Spacer(minLength: 0)
                }
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 480)
        .onDisappear { detector.stop() }
    }

    // MARK: Scope

    /// Saved keyboards that are not connected.
    private var savedOnly: [KeyboardDevice] {
        model.settings.keyboards.map(\.device).filter { saved in !monitor.devices.contains { $0.scope == saved.scope } }
    }

    /// The picked keyboard; "All keyboards" once it is neither connected nor saved any more.
    private var current: Scope {
        device(for: scope) == nil ? .all : scope
    }

    private var selection: Binding<Scope> {
        Binding(get: { current }, set: { scope = $0 })
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
            }
            if list.isEmpty {
                Text("No mappings yet. Add one below.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                // As tall as its rows; scrolls only when the window is too short.
                ViewThatFits(in: .vertical) {
                    rows(list)
                    ScrollView { rows(list) }
                }
            }
        }
    }

    private func rows(_ list: [Mapping]) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { mapping in
                if mapping.id != list.first?.id { Divider() }
                row(mapping)
            }
        }
        .modifier(GlassCard())
    }

    private func row(_ mapping: Mapping) -> some View {
        HStack(spacing: 8) {
            KeyMenu(usage: mapping.from) { model.setFrom($0, for: mapping.id, in: current) }
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            KeyMenu(usage: mapping.to) { model.setTo($0, for: mapping.id, in: current) }
            Spacer()
            Toggle("Enabled", isOn: Binding(
                get: { mapping.enabled },
                set: { model.setEnabled($0, for: mapping.id, in: current) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            Button { model.remove(mapping.id, in: current) } label: {
                Label("Remove", systemImage: "trash").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
        .padding(.vertical, 6)
    }

    // MARK: New mapping

    private var newMappingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New mapping").font(.headline)
            HStack(spacing: 8) {
                KeyMenu(usage: newFrom) { newFrom = $0 }
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                KeyMenu(usage: newTo) { newTo = $0 }
            }
            if let detected = detector.detected, !detector.isDetecting {
                VStack(alignment: .leading, spacing: 6) {
                    Text(description(detected))
                        .font(.callout)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Button("Use as From") { newFrom = detected.usage }
                        Button("Use as To") { newTo = detected.usage }
                        if let device = detected.device {
                            Button("Use this keyboard") { scope = device.scope }
                                .disabled(current == device.scope)
                        }
                    }
                    .controlSize(.small)
                }
            }
            if detector.permissionDenied && !detector.isDetecting {
                Text("Input Monitoring access is needed to detect keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Settings") { detector.openInputMonitoringSettings() }
                    .controlSize(.small)
            }
            if let hint = detector.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if detector.isDetecting {
                    ProgressView().controlSize(.small)
                    Text("Press any key…")
                    Button("Cancel") { detector.stop() }
                        .controlSize(.small)
                } else {
                    Button { detector.start() } label: {
                        Label("Detect key", systemImage: "keyboard.badge.ellipsis")
                    }
                }
                Spacer()
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(newFrom == nil || newTo == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCard())
    }

    private func add() {
        guard let newFrom, let newTo else { return }
        guard model.add(from: newFrom, to: newTo, in: device(for: current)) else { return }
        self.newFrom = nil
        self.newTo = nil
        detector.detected = nil
    }

    private func description(_ detected: DetectedKey) -> String {
        let key = detected.key.map { "\($0.label) (\($0.name))" } ?? KeyMenu.label(detected.usage)
        return "\(key) · \(detected.device?.name ?? "Unknown keyboard")"
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Import…", action: importSettings)
            Button("Export…", action: exportSettings)
        }
    }

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

/// A key-cap button opening the key catalog by category, with a checkmark on the current key.
private struct KeyMenu: View {
    let usage: UInt64?
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
                    .font(usage == nil ? .callout : .system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(usage == nil ? .secondary : .primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Liquid Glass on macOS 26+, a material card before.
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.padding(12).glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
