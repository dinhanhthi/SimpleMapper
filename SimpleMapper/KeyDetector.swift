import AppKit
import IOKit.hid

/// A key pressed while detecting, with the keyboard it came from.
struct DetectedKey {
    let usage: UInt64
    let key: Key?
    let device: KeyboardDevice?
}

/// Detects one raw key press with a separate IOHIDManager, opened (never seized) only while detecting.
@MainActor
final class KeyDetector: ObservableObject {
    @Published private(set) var isDetecting = false
    @Published var detected: DetectedKey?
    @Published var permissionDenied = false
    @Published var hint: String?

    private var manager: IOHIDManager?
    private var eventMonitor: Any?
    private var timeoutTask: Task<Void, Never>?

    func start() {
        guard !isDetecting else { return }
        detected = nil
        hint = nil
        permissionDenied = false
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            break
        case kIOHIDAccessTypeDenied:
            permissionDenied = true
            return
        default:
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            hint = "Allow SimpleMapper in System Settings > Privacy & Security > Input Monitoring, then click Detect again."
            return
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let detector = Unmanaged<KeyDetector>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { detector.handle(value) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.manager = manager
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            hint = "Quit and relaunch SimpleMapper after granting access, and quit Karabiner-Elements if it is running."
            stop()
            return
        }
        isDetecting = true
        // Swallow keys so Escape/Return/Space do not trigger window controls while detecting.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { _ in nil }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            self.manager = nil
        }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        isDetecting = false
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Keyboard page 0x07 keys 0x04...0xE7 (0x00-0x03 are error/rollover codes) and `fn` (page 0xFF, usage 0x03).
    nonisolated static func acceptedUsage(page: UInt32, usage: UInt32) -> UInt64? {
        guard (page == 0x07 && (0x04...0xE7).contains(usage)) || (page == 0xFF && usage == 0x03) else { return nil }
        return UInt64(page) << 32 | UInt64(usage)
    }

    private func handle(_ value: IOHIDValue) {
        guard isDetecting, IOHIDValueGetIntegerValue(value) == 1 else { return }
        let element = IOHIDValueGetElement(value)
        // Combo receivers expose pointer axes on the keyboard interface; a mouse move is not a key press.
        guard !IOHIDElementIsRelative(element) else { return }
        let page = IOHIDElementGetUsagePage(element)
        let rawUsage = IOHIDElementGetUsage(element)
        // Keyboard page usages 0x00-0x03 are error/rollover codes, not key presses.
        guard !(page == 0x07 && rawUsage <= 0x03) else { return }
        let device = IOHIDElementGetDevice(element)
        // Karabiner's virtual keyboard re-emits the keys it seizes.
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        guard !name.contains("Karabiner") else { return }
        // Stop on the first key press of any page; defer stop() since it releases the manager running this callback.
        isDetecting = false
        DispatchQueue.main.async { [weak self] in self?.stop() }
        guard let usage = Self.acceptedUsage(page: page, usage: rawUsage) else {
            hint = "That key can't be remapped by SimpleMapper. Try another key."
            return
        }
        detected = DetectedKey(usage: usage, key: KeyCatalog.key(usage: usage), device: KeyboardDevice.keyboard(device))
    }
}
