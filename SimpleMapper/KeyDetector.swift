import AppKit
import IOKit.hid

/// A key pressed while detecting, with the keyboard it came from.
struct DetectedKey {
    let usage: UInt64
    let key: Key?
    let device: KeyboardDevice?
    /// Modifier usages held when the key was pressed (a keyboard's built-in shortcut sends them with the key).
    var modifiers: [UInt64] = []

    /// The held modifiers as symbols in macOS order (⌃⌥⇧⌘), left and right alike.
    var modifierSymbols: String {
        let ids = Set(modifiers.map { $0 & 0xFFFF_FFFF })
        let symbols: [(left: UInt64, right: UInt64, symbol: String)] = [
            (0xE0, 0xE4, "⌃"), (0xE2, 0xE6, "⌥"), (0xE1, 0xE5, "⇧"), (0xE3, 0xE7, "⌘"),
        ]
        return symbols.filter { ids.contains($0.left) || ids.contains($0.right) }.map(\.symbol).joined()
    }

    /// The key's label after its held modifiers, e.g. "⇧⌘3".
    var label: String {
        modifierSymbols + (key?.label ?? KeyMenu.label(usage))
    }
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
    /// Modifiers pressed since Detect started, in press order, and whether a key already ended the detection.
    private var heldModifiers: [UInt64] = []
    private var keyPressed = false

    func start() {
        guard !isDetecting else { return }
        detected = nil
        hint = nil
        heldModifiers = []
        keyPressed = false
        permissionDenied = false
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            break
        case kIOHIDAccessTypeDenied:
            permissionDenied = true
            return
        default:
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            permissionDenied = true
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
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            stop()
            if result == kIOReturnNotPermitted {
                // Listed as allowed, but macOS still blocks this build (a stale grant, e.g. after an update).
                permissionDenied = true
                hint = "If SimpleMapper is already allowed, remove it from the list with −, add it again, then relaunch SimpleMapper."
            } else {
                hint = "Quit Karabiner-Elements if it is running, then click Detect again (error \(String(format: "0x%x", result)))."
            }
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

    /// Input Monitoring is granted. Read live, so a grant in System Settings shows without a relaunch.
    var hasAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows the system prompt the first time; macOS does not prompt again after a denial, so then opens System Settings.
    func requestAccess() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        } else {
            openInputMonitoringSettings()
        }
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
        guard isDetecting else { return }
        let pressed = IOHIDValueGetIntegerValue(value) == 1
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
        // A modifier counts only when released with no other key pressed; until then it is held for a combination.
        if page == 0x07, (0xE0...0xE7).contains(rawUsage) {
            let usage = UInt64(page) << 32 | UInt64(rawUsage)
            if pressed {
                if !heldModifiers.contains(usage) { heldModifiers.append(usage) }
            } else if !keyPressed, heldModifiers.contains(usage) {
                keyPressed = true
                finish(page: page, usage: rawUsage, device: device)
            }
            return
        }
        guard pressed, !keyPressed else { return }
        // The first other key press of any page ends the detection. Wait a moment: a keyboard can report the
        // modifiers of a built-in shortcut after the key.
        keyPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.finish(page: page, usage: rawUsage, device: device)
        }
    }

    private func finish(page: UInt32, usage rawUsage: UInt32, device: IOHIDDevice) {
        guard isDetecting else { return }
        // Defer stop() since it releases the manager that may be running the callback.
        isDetecting = false
        DispatchQueue.main.async { [weak self] in self?.stop() }
        guard let usage = Self.acceptedUsage(page: page, usage: rawUsage) else {
            hint = "That key can't be remapped by SimpleMapper. Try another key."
            return
        }
        let detected = DetectedKey(usage: usage, key: KeyCatalog.key(usage: usage), device: KeyboardDevice.keyboard(device),
                                   modifiers: heldModifiers.filter { $0 != usage })
        if !detected.modifiers.isEmpty, let key = detected.key {
            hint = "Pressed with \(detected.modifierSymbols) held. If this one key sends the whole combination by itself "
                + "(a shortcut built into the keyboard), SimpleMapper can't remap or turn it off alone: it only sees "
                + "\(key.label), and remapping that changes every \(key.label) press."
        }
        self.detected = detected
    }
}
