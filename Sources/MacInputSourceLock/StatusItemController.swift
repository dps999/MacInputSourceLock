import AppKit
import Foundation

struct EnforcerStatus {
    let targetInputSourceID: String
    let currentInputSourceID: String?
    let accessibilityTrusted: Bool
    let lastEvent: String
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let stateItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let targetItem = NSMenuItem(title: "Target: --", action: nil, keyEquivalent: "")
    private let currentItem = NSMenuItem(title: "Current: --", action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Accessibility: checking…", action: nil, keyEquivalent: "")
    private let startupItem = NSMenuItem(title: "Run at Startup", action: nil, keyEquivalent: "")
    private let eventItem = NSMenuItem(title: "Last event: startup", action: nil, keyEquivalent: "")
    var onToggleRunAtStartup: ((Bool) -> Void)?

    override init() {
        super.init()
        configureStatusItem()
        configureMenu()
    }

    func update(status: EnforcerStatus) {
        stateItem.title = status.accessibilityTrusted ? "MacInputSourceLock is running" : "Waiting for Accessibility permission"
        targetItem.title = "Target: \(status.targetInputSourceID)"
        currentItem.title = "Current: \(status.currentInputSourceID ?? "unknown")"
        accessibilityItem.title = "Accessibility: \(status.accessibilityTrusted ? "granted" : "not granted")"
        eventItem.title = "Last event: \(status.lastEvent)"
        updateButton(accessibilityTrusted: status.accessibilityTrusted)
    }

    func setRunAtStartupEnabled(_ enabled: Bool) {
        startupItem.state = enabled ? .on : .off
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "MacInputSourceLock")
        button.image?.isTemplate = true
        button.title = " EN"
        button.imagePosition = .imageLeading
        button.toolTip = "MacInputSourceLock"
    }

    private func configureMenu() {
        menu.autoenablesItems = false

        stateItem.isEnabled = false
        targetItem.isEnabled = false
        currentItem.isEnabled = false
        accessibilityItem.isEnabled = false
        startupItem.target = self
        startupItem.action = #selector(toggleRunAtStartup(_:))
        eventItem.isEnabled = false

        let openAccessibilityItem = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openAccessibilityItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self

        menu.items = [
            stateItem,
            targetItem,
            currentItem,
            accessibilityItem,
            startupItem,
            eventItem,
            .separator(),
            openAccessibilityItem,
            quitItem,
        ]

        statusItem.menu = menu
    }

    private func updateButton(accessibilityTrusted: Bool) {
        guard let button = statusItem.button else {
            return
        }

        button.toolTip = accessibilityTrusted
            ? "MacInputSourceLock is running"
            : "MacInputSourceLock is waiting for Accessibility permission"
    }

    @objc
    private func toggleRunAtStartup(_ sender: NSMenuItem) {
        onToggleRunAtStartup?(sender.state != .on)
    }

    @objc
    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
