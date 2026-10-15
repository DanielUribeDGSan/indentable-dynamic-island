import AppKit
import ApplicationServices

@_silgen_name("IsSecureEventInputEnabled")
private func IsSecureEventInputEnabled() -> Bool

final class HotkeyMonitor {
    private let onTrigger: () -> Void
    private let shouldIgnore: () -> Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var commandCount = 0
    private var lastCommand = Date.distantPast
    private var lastTrigger = Date.distantPast

    init(onTrigger: @escaping () -> Void, shouldIgnore: @escaping () -> Bool) {
        self.onTrigger = onTrigger
        self.shouldIgnore = shouldIgnore
    }

    func start() {
        if tap != nil { return }
        if installTap() {
            removeMonitors()
            return
        }
        if globalMonitor == nil {
            installMonitors()
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, userInfo in
                if let userInfo {
                    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                    monitor.receive(event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func installMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.receive(keyCode: event.keyCode, flags: event.modifierFlags, autorepeat: event.isARepeat)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    private func receive(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        var modifiers = NSEvent.ModifierFlags()
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        receive(keyCode: keyCode, flags: modifiers, autorepeat: autorepeat)
    }

    private func receive(keyCode: UInt16, flags: NSEvent.ModifierFlags, autorepeat: Bool) {
        let isCommandKey = keyCode == 55 || keyCode == 54
        let pressed = flags.contains(.command)
        guard isCommandKey, pressed, !autorepeat else { return }
        if shouldIgnore() || IsSecureEventInputEnabled() {
            commandCount = 0
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastCommand) < 0.08 {
            return
        }
        if now.timeIntervalSince(lastCommand) > 0.6 {
            commandCount = 0
        }
        lastCommand = now
        commandCount += 1
        if commandCount >= 3 {
            commandCount = 0
            guard now.timeIntervalSince(lastTrigger) > 0.8 else { return }
            lastTrigger = now
            DispatchQueue.main.async { [onTrigger] in
                onTrigger()
            }
        }
    }
}

final class SelectionMonitor {
    private weak var state: IslandState?
    private var timer: Timer?
    private var reading = false
    var onTrustChanged: ((Bool) -> Void)?

    init(state: IslandState) {
        self.state = state
    }

    func start() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func promptForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func tick() {
        let trusted = AXIsProcessTrusted()
        if trusted != state?.accessibilityTrusted {
            state?.accessibilityTrusted = trusted
            onTrustChanged?(trusted)
        }
        guard trusted, state?.isPresented == true, state?.phase == .live else { return }
        guard !reading else { return }
        reading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = SelectionReader.current()
            DispatchQueue.main.async {
                if let text {
                    self?.state?.applySelection(text)
                }
                self?.reading = false
            }
        }
    }
}

enum SelectionReader {
    private static var preparedPIDs = Set<pid_t>()

    static func current() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        prepareFrontApp()
        let system = AXUIElementCreateSystemWide()
        if let focused = copyElement(system, kAXFocusedUIElementAttribute as CFString) {
            var pid: pid_t = 0
            AXUIElementGetPid(focused, &pid)
            if pid != getpid(), !isSecure(focused) {
                if let text = fromChain(focused) { return text }
                if let window = copyElement(focused, kAXWindowAttribute as CFString), let text = fromWindow(window) {
                    return text
                }
            }
        }
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else {
            return nil
        }
        let application = AXUIElementCreateApplication(front.processIdentifier)
        guard let window = copyElement(application, kAXFocusedWindowAttribute as CFString) else { return nil }
        return fromWindow(window)
    }

    private static func prepareFrontApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        guard pid != getpid(), preparedPIDs.insert(pid).inserted else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private static func fromChain(_ start: AXUIElement) -> String? {
        var current: AXUIElement? = start
        for _ in 0..<14 {
            guard let element = current else { break }
            if isSecure(element) { return nil }
            if let text = directSelection(element) { return text }
            current = copyElement(element, kAXParentAttribute as CFString)
        }
        return nil
    }

    private static func fromWindow(_ window: AXUIElement) -> String? {
        if let text = directSelection(window) { return text }
        var budget = 90
        if let web = find(role: "AXWebArea", in: window, depth: 6, budget: &budget), let text = directSelection(web) {
            return text
        }
        budget = 40
        if let area = find(role: "AXTextArea", in: window, depth: 5, budget: &budget), let text = directSelection(area) {
            return text
        }
        return nil
    }

    private static func directSelection(_ element: AXUIElement) -> String? {
        if isSecure(element) { return nil }
        if let text = usable(copyString(element, kAXSelectedTextAttribute as CFString)) { return text }
        if let text = usable(stringForRange(element)) { return text }
        if let text = usable(stringForMarker(element)) { return text }
        return nil
    }

    private static func stringForRange(_ element: AXUIElement) -> String? {
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            range,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private static func stringForMarker(_ element: AXUIElement) -> String? {
        var marker: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &marker) == .success,
              let marker else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            marker,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private static func find(role: String, in element: AXUIElement, depth: Int, budget: inout Int) -> AXUIElement? {
        guard budget > 0, depth >= 0 else { return nil }
        budget -= 1
        if copyString(element, kAXRoleAttribute as CFString) == role { return element }
        guard let children = copyElements(element, kAXChildrenAttribute as CFString) else { return nil }
        for child in children.prefix(30) {
            if let found = find(role: role, in: child, depth: depth - 1, budget: &budget) {
                return found
            }
        }
        return nil
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        copyString(element, kAXSubroleAttribute as CFString) == "AXSecureTextField"
    }

    private static func usable(_ text: String?) -> String? {
        guard let text else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyElements(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else { return nil }
        return value as? [AXUIElement]
    }

    private static func copyString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
