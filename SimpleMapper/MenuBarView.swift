import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: KeyboardMonitor
    @ObservedObject var detector: KeyDetector
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SimpleMapper").font(.headline)
                Spacer()
                Toggle("", isOn: $model.enabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }

            GlassCards {
                VStack(spacing: 12) {
                    mappingCard
                    detectCard
                }
            }

            Picker("Keyboard", selection: keyboardSelection) {
                Text("All keyboards").tag(String?.none)
                ForEach(monitor.devices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
                if let saved = model.savedDevice, !monitor.devices.contains(where: { $0.id == saved.id }) {
                    Text("\(saved.name) (not connected)").tag(Optional(saved.id))
                }
            }
            .pickerStyle(.menu)

            if !model.status.isEmpty {
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                    .toggleStyle(.checkbox)
                HStack {
                    Button("Check for Updates…", action: updater.checkForUpdates)
                        .disabled(!updater.canCheck)
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                }
                .buttonStyle(.borderless)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 300)
        .onDisappear { detector.stop() }
    }

    private var mappingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            keyRow("From", usage: $model.fromUsage)
            Image(systemName: "arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            keyRow("To", usage: $model.toUsage)
        }
        .modifier(GlassCard())
    }

    private func keyRow(_ title: String, usage: Binding<UInt64>) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(Category.allCases, id: \.self) { category in
                    Menu(category.title) {
                        ForEach(KeyCatalog.all.filter { $0.category == category }) { key in
                            Toggle(key.label, isOn: Binding(
                                get: { KeyCatalog.key(usage: usage.wrappedValue)?.name == key.name },
                                set: { if $0 { usage.wrappedValue = key.usage } }
                            ))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(label(usage.wrappedValue))
                        .font(.system(.callout, design: .monospaced).weight(.medium))
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

    private var detectCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if detector.isDetecting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Press any key…")
                    Spacer()
                    Button("Cancel") { detector.stop() }
                        .controlSize(.small)
                }
            } else {
                if detector.permissionDenied {
                    Text("Input Monitoring access is needed to detect keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") { detector.openInputMonitoringSettings() }
                        .controlSize(.small)
                }
                if let detected = detector.detected {
                    Text(description(detected))
                        .font(.callout)
                        .lineLimit(2)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Button("Use as From") { model.use(detected, as: .from) }
                            Button("Use as To") { model.use(detected, as: .to) }
                        }
                        if let device = detected.device {
                            Button("Use this keyboard") { model.useKeyboard(device) }
                        }
                    }
                    .controlSize(.small)
                }
                Button { detector.start() } label: {
                    Label("Detect key", systemImage: "keyboard.badge.ellipsis")
                }
            }
            if let hint = detector.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCard())
    }

    private var keyboardSelection: Binding<String?> {
        Binding(
            get: {
                guard model.scope != .all else { return nil }
                return (monitor.devices + [model.savedDevice].compactMap { $0 }).first { $0.scope == model.scope }?.id
            },
            set: { id in
                if id == nil {
                    model.useAllKeyboards()
                } else if let device = (monitor.devices + [model.savedDevice].compactMap { $0 }).first(where: { $0.id == id }) {
                    model.useKeyboard(device)
                }
            }
        )
    }

    private func label(_ usage: UInt64) -> String {
        KeyCatalog.key(usage: usage)?.label ?? String(format: "0x%llX", usage)
    }

    private func description(_ detected: DetectedKey) -> String {
        let key = detected.key.map { "\($0.label) (\($0.name))" } ?? label(detected.usage)
        return "\(key) · \(detected.device?.name ?? "Unknown keyboard")"
    }
}

/// Liquid Glass on macOS 26+, a material card before.
private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.padding(12).glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Groups glass cards in a `GlassEffectContainer` on macOS 26+.
private struct GlassCards<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}
