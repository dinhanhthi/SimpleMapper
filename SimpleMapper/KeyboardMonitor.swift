import Foundation
import IOKit.hid

/// A connected keyboard, identified like `Remapper.matchingJSON` matches it.
struct KeyboardDevice: Identifiable, Hashable, Codable {
    let vendorID: Int
    let productID: Int
    let builtIn: Bool
    let name: String

    var id: String { "\(vendorID):\(productID):\(builtIn)" }
    var scope: Scope { .device(vendorID: vendorID, productID: productID, builtIn: builtIn) }

    /// The Apple Silicon built-in keyboard has no vendor/product IDs (0 here); hidutil matches it by `Built-In`.
    static func keyboard(_ device: IOHIDDevice) -> KeyboardDevice? {
        func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
        let vendorID = property(kIOHIDVendorIDKey) as? Int
        let productID = property(kIOHIDProductIDKey) as? Int
        let builtIn = (property("Built-In") as? Bool) ?? false
        guard builtIn || (vendorID != nil && productID != nil) else { return nil }
        let name = (property(kIOHIDProductKey) as? String) ?? (builtIn ? "Built-in Keyboard" : "Keyboard")
        return KeyboardDevice(vendorID: vendorID ?? 0, productID: productID ?? 0, builtIn: builtIn, name: name)
    }
}

/// Lists keyboards via IOHIDManager matching only. The manager is never opened, so no Input Monitoring prompt.
@MainActor
final class KeyboardMonitor: ObservableObject {
    @Published private(set) var devices: [KeyboardDevice] = []
    /// Called (debounced 0.5 s) when a keyboard is attached after launch.
    var onAttach: (() -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    /// Devices present at launch: their matching callbacks fire after scheduling and are not attaches.
    private var initialDevices: Set<IOHIDDevice> = []
    private var attachTask: Task<Void, Never>?

    init() {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        initialDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.deviceMatched(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        refresh()
        guard initialDevices.remove(device) == nil else { return }
        attachTask?.cancel()
        attachTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.onAttach?()
        }
    }

    private func refresh() {
        let all = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        var seen = Set<String>()
        devices = all.compactMap(KeyboardDevice.keyboard)
            .filter { !$0.name.contains("Karabiner") && seen.insert($0.id).inserted }
            .sorted { ($0.builtIn ? 0 : 1, $0.name) < ($1.builtIn ? 0 : 1, $1.name) }
    }
}
