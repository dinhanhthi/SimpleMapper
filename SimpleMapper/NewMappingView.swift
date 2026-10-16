import SwiftUI

/// The "New mapping" window: From and To keys, Detect key, Cancel and Add.
struct NewMappingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var detector: KeyDetector
    @ObservedObject var selection: KeyboardSelection
    /// Adds the mapping to the picked keyboard's list; returns whether it was accepted.
    let add: (UInt64, UInt64) -> Bool
    /// Closes the window; set by its owner.
    var close: () -> Void = {}
    @State private var from: UInt64?
    @State private var to: UInt64?
    @State private var addFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                KeyMenu(usage: from, tint: .from) { from = $0 }
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                KeyMenu(usage: to, tint: .to) { to = $0 }
            }
            if let detected = detector.detected, !detector.isDetecting {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(detected.key?.label ?? KeyMenu.label(detected.usage))
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .modifier(KeyCap())
                        if let key = detected.key {
                            Text(key.name)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text("· \(detected.device?.name ?? "Unknown keyboard")")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Button("Use as From") { from = detected.usage; detector.detected = nil }
                        Button("Use as To") { to = detected.usage; detector.detected = nil }
                        if let device = detected.device {
                            Button("Use this keyboard") { selection.scope = device.scope }
                                .disabled(selection.scope == device.scope)
                        }
                    }
                    .controlSize(.small)
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
            if addFailed, let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if detector.isDetecting {
                    ProgressView().controlSize(.small)
                    Text("Press any key…")
                    Button("Stop") { detector.stop() }
                        .controlSize(.small)
                } else {
                    Button { detector.start() } label: {
                        Label("Detect key", systemImage: "keyboard.badge.ellipsis")
                    }
                }
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(from == nil || to == nil)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func submit() {
        guard let from, let to else { return }
        addFailed = !add(from, to)
        if !addFailed { close() }
    }
}
