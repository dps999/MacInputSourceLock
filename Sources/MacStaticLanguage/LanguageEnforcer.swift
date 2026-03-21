import AppKit
import ApplicationServices
import Foundation

private struct FocusSignature: Equatable {
    let processID: pid_t
    let windowToken: String
}

@MainActor
final class LanguageEnforcer: NSObject {
    private let configuration: Configuration
    private let inputSourceManager = InputSourceManager()
    private var focusTimer: Timer?
    private var permissionTimer: Timer?
    private var lastFocusSignature: FocusSignature?
    private var hasPromptedForAccessibility = false

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

        observeWorkspaceNotifications()
        forceInputSource(reason: "startup")
        startMonitoringIfTrusted()
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

    @objc
    private func activeApplicationDidChange(_ notification: Notification) {
        lastFocusSignature = nil
        forceInputSource(reason: "application activation")
        evaluateFocusChange(force: true)
    }

    private func startMonitoringIfTrusted() {
        if accessibilityTrusted(prompt: configuration.promptForAccessibility) {
            scheduleFocusTimer()
            evaluateFocusChange(force: true)
            return
        }

        schedulePermissionTimer()
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
        evaluateFocusChange()
    }

    @objc
    private func handlePermissionTimer(_ timer: Timer) {
        if accessibilityTrusted(prompt: false) {
            print("Accessibility permission granted. Focus monitoring enabled.")
            timer.invalidate()
            permissionTimer = nil
            scheduleFocusTimer()
            evaluateFocusChange(force: true)
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
            print("Accessibility permission is required. Approve MacStaticLanguage in System Settings > Privacy & Security > Accessibility.")
        }
        return trusted
    }

    private func evaluateFocusChange(force: Bool = false) {
        guard accessibilityTrusted(prompt: false) else {
            return
        }

        guard let signature = currentFocusSignature() else {
            return
        }

        if force || signature != lastFocusSignature {
            lastFocusSignature = signature
            forceInputSource(reason: "focus change")
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
        do {
            let changed = try inputSourceManager.ensureSelected(inputSourceID: configuration.inputSourceID)
            if changed {
                print("Switched input source to \(configuration.inputSourceID) (\(reason)).")
            }
        } catch {
            fputs("MacStaticLanguage error: \(error.localizedDescription)\n", stderr)
        }
    }
}
