import AppKit
import ApplicationServices
import Foundation

private struct FocusSignature: Equatable {
    let processID: pid_t
    let windowToken: String
}

@MainActor
final class LanguageEnforcer: NSObject {
    private static let enforcementRetryDelays: [TimeInterval] = [0.12, 0.35, 0.7]
    private static let spaceKeyCode: UInt16 = 49
    private static let spotlightBundleIdentifier = "com.apple.Spotlight"
    private static let debugDateFormatter = ISO8601DateFormatter()

    private let configuration: Configuration
    private let inputSourceManager = InputSourceManager()
    private var focusTimer: Timer?
    private var permissionTimer: Timer?
    private var spotlightEventTap: CFMachPort?
    private var spotlightEventSource: CFRunLoopSource?
    private var wasSpotlightActive = false
    private var lastFocusSignature: FocusSignature?
    private var enforcementGeneration = 0
    private var hasPromptedForAccessibility = false
    var onStatusChange: ((EnforcerStatus) -> Void)?

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init()
    }

    func start() {
        if configuration.listInputSources {
            printInputSources()
            NSApp.terminate(nil)
            return
        }

        debugLog("start target=\(configuration.inputSourceID) promptForAccessibility=\(configuration.promptForAccessibility) current=\(inputSourceManager.currentInputSourceID() ?? "nil")")
        observeWorkspaceNotifications()
        observeSpotlightShortcut()
        reinforceInputSource(reason: "startup")
        startMonitoringIfTrusted()
        publishStatus(lastEvent: "startup")
    }

    private func printInputSources() {
        let sources = inputSourceManager.listSelectableKeyboardInputSources()
        if sources.isEmpty {
            print("No selectable keyboard input sources were found.")
            return
        }

        for source in sources {
            let marker = source.isSelected ? "*" : " "
            print("\(marker) \(source.id) | \(source.name)")
        }
    }

    private func observeWorkspaceNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    private func observeSpotlightShortcut() {
        guard spotlightEventTap == nil else {
            return
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let enforcer = Unmanaged<LanguageEnforcer>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                Task { @MainActor in
                    enforcer.debugLog("spotlight event tap disabled type=\(type.rawValue), re-enabling")
                    enforcer.enableSpotlightEventTap()
                }
                return Unmanaged.passUnretained(event)
            }

            guard type == .keyDown, enforcer.isSpotlightShortcut(event) else {
                return Unmanaged.passUnretained(event)
            }

            Task { @MainActor in
                enforcer.handleSpotlightShortcut()
            }

            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLog("failed to create spotlight event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        spotlightEventTap = tap
        spotlightEventSource = source
        enableSpotlightEventTap()
        debugLog("spotlight event tap created")
    }

    private func enableSpotlightEventTap() {
        guard let spotlightEventTap else {
            return
        }

        CGEvent.tapEnable(tap: spotlightEventTap, enable: true)
    }

    private func isSpotlightShortcut(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(Self.spaceKeyCode) else {
            return false
        }

        let modifiers = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn])
        return modifiers == .maskCommand || modifiers == [.maskCommand, .maskAlternate]
    }

    private func handleSpotlightShortcut() {
        debugLog("spotlight shortcut detected current=\(inputSourceManager.currentInputSourceID() ?? "nil")")
        lastFocusSignature = nil
        reinforceInputSource(reason: "spotlight shortcut")
    }

    @objc
    private func activeApplicationDidChange(_ notification: Notification) {
        let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) ?? NSWorkspace.shared.frontmostApplication
        debugLog("application activation bundle=\(app?.bundleIdentifier ?? "nil") name=\(app?.localizedName ?? "nil") current=\(inputSourceManager.currentInputSourceID() ?? "nil")")
        lastFocusSignature = nil
        reinforceInputSource(reason: "application activation")

        guard accessibilityTrusted(prompt: false),
              let signature = currentFocusSignature() else {
            return
        }

        lastFocusSignature = signature
    }

    private func startMonitoringIfTrusted() {
        let trusted = accessibilityTrusted(prompt: configuration.promptForAccessibility)
        debugLog("start monitoring accessibilityTrusted=\(trusted)")

        scheduleFocusTimer()
        evaluateFocusChange(force: true, reason: "initial focus check")

        if !trusted {
            schedulePermissionTimer()
        }
    }

    private func scheduleFocusTimer() {
        guard focusTimer == nil else {
            return
        }

        focusTimer = Timer.scheduledTimer(
            timeInterval: configuration.pollInterval,
            target: self,
            selector: #selector(handleFocusTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(focusTimer!, forMode: .common)
        focusTimer?.tolerance = min(configuration.pollInterval * 0.5, 0.25)
    }

    private func schedulePermissionTimer() {
        guard permissionTimer == nil else {
            return
        }

        permissionTimer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(handlePermissionTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(permissionTimer!, forMode: .common)
    }

    @objc
    private func handleFocusTimer(_ timer: Timer) {
        handleSpotlightActivation()
        evaluateFocusChange(reason: "focus change")
    }

    private func handleSpotlightActivation() {
        let isSpotlightActive = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.spotlightBundleIdentifier)
            .contains(where: \.isActive)

        if isSpotlightActive != wasSpotlightActive {
            debugLog("spotlight active changed to \(isSpotlightActive) current=\(inputSourceManager.currentInputSourceID() ?? "nil")")
        }

        defer { wasSpotlightActive = isSpotlightActive }

        guard isSpotlightActive, !wasSpotlightActive else {
            return
        }

        lastFocusSignature = nil
        reinforceInputSource(reason: "spotlight activation")
    }

    @objc
    private func handlePermissionTimer(_ timer: Timer) {
        if accessibilityTrusted(prompt: false) {
            debugLog("permission timer detected accessibility granted")
            timer.invalidate()
            permissionTimer = nil
            scheduleFocusTimer()
            evaluateFocusChange(force: true, reason: "initial focus check")
        } else {
            debugLog("permission timer waiting for accessibility")
            publishStatus(lastEvent: "waiting for accessibility")
        }
    }

    private func accessibilityTrusted(prompt: Bool) -> Bool {
        let shouldPrompt = prompt && !hasPromptedForAccessibility
        if shouldPrompt {
            hasPromptedForAccessibility = true
        }

        let options = ["AXTrustedCheckOptionPrompt": shouldPrompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted && shouldPrompt {
            print("Accessibility permission is required. Approve MacInputSourceLock in System Settings > Privacy & Security > Accessibility.")
        }
        if configuration.debugLogging {
            debugLog("accessibilityTrusted prompt=\(prompt) shouldPrompt=\(shouldPrompt) trusted=\(trusted)")
        }
        return trusted
    }

    private func evaluateFocusChange(force: Bool = false, reason: String = "focus change") {
        guard let signature = currentFocusSignature() else {
            if force {
                reinforceInputSource(reason: reason)
            }
            return
        }

        if force || signature != lastFocusSignature {
            debugLog("focus change reason=\(reason) force=\(force) signature=\(signature.processID)|\(signature.windowToken) current=\(inputSourceManager.currentInputSourceID() ?? "nil")")
            lastFocusSignature = signature
            reinforceInputSource(reason: reason)
        }
    }

    private func reinforceInputSource(reason: String) {
        enforcementGeneration += 1
        let generation = enforcementGeneration
        debugLog("reinforce reason=\(reason) generation=\(generation)")

        forceInputSource(reason: reason)

        for delay in Self.enforcementRetryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.enforcementGeneration == generation else {
                        return
                    }

                    self.forceInputSource(reason: "\(reason) retry")
                }
            }
        }
    }

    private func currentFocusSignature() -> FocusSignature? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let windowToken = focusedElementToken(for: app.processIdentifier) ?? app.bundleIdentifier ?? app.localizedName ?? "pid:\(app.processIdentifier)"
        return FocusSignature(processID: app.processIdentifier, windowToken: windowToken)
    }

    private func focusedElementToken(for processID: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(processID)

        if let focusedWindow = copyElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement) {
            return token(for: focusedWindow)
        }

        if let focusedElement = copyElementAttribute(kAXFocusedUIElementAttribute as CFString, from: appElement) {
            return token(for: focusedElement)
        }

        return nil
    }

    private func token(for element: AXUIElement) -> String {
        let hash = CFHash(element)
        let role = copyStringAttribute(kAXRoleAttribute as CFString, from: element) ?? "unknown-role"
        let title = copyStringAttribute(kAXTitleAttribute as CFString, from: element) ?? "untitled"
        return "\(hash)|\(role)|\(title)"
    }

    private func copyElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else {
            return nil
        }

        return value as? String
    }

    private func forceInputSource(reason: String) {
        let before = inputSourceManager.currentInputSourceID() ?? "nil"
        do {
            let changed = try inputSourceManager.ensureSelected(inputSourceID: configuration.inputSourceID)
            let after = inputSourceManager.currentInputSourceID() ?? "nil"
            debugLog("forceInputSource reason=\(reason) before=\(before) after=\(after) changed=\(changed)")
            publishStatus(lastEvent: changed ? "switched on \(reason)" : "already English on \(reason)")
        } catch {
            fputs("MacInputSourceLock error: \(error.localizedDescription)\n", stderr)
            debugLog("forceInputSource error reason=\(reason) before=\(before) error=\(error.localizedDescription)")
            publishStatus(lastEvent: "error: \(error.localizedDescription)")
        }
    }

    private func debugLog(_ message: String) {
        guard configuration.debugLogging else {
            return
        }

        let timestamp = Self.debugDateFormatter.string(from: Date())
        print("[debug \(timestamp)] \(message)")
    }

    private func publishStatus(lastEvent: String) {
        onStatusChange?(EnforcerStatus(
            targetInputSourceID: configuration.inputSourceID,
            currentInputSourceID: inputSourceManager.currentInputSourceID(),
            accessibilityTrusted: accessibilityTrusted(prompt: false),
            lastEvent: lastEvent
        ))
    }
}
