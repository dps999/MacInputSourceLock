import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configuration: Configuration
    private var enforcer: LanguageEnforcer?
    private var statusItemController: StatusItemController?
    private let launchAgentManager: LaunchAgentManager?

    init(configuration: Configuration) {
        self.configuration = configuration
        self.launchAgentManager = try? LaunchAgentManager(
            configuration: configuration,
            executableURL: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !configuration.listInputSources {
            statusItemController = StatusItemController()
            statusItemController?.setRunAtStartupEnabled(launchAgentManager?.currentState().enabled ?? false)
            statusItemController?.onToggleRunAtStartup = { [weak self] enabled in
                self?.toggleRunAtStartup(enabled: enabled)
            }
        }

        enforcer = LanguageEnforcer(configuration: configuration)
        enforcer?.onStatusChange = { [weak self] status in
            self?.statusItemController?.update(status: status)
        }
        enforcer?.start()
    }

    private func toggleRunAtStartup(enabled: Bool) {
        guard let launchAgentManager else {
            presentErrorAlert(message: "Run at Startup is unavailable because the executable path could not be resolved.")
            statusItemController?.setRunAtStartupEnabled(false)
            return
        }

        do {
            let result = try enabled ? launchAgentManager.enable() : launchAgentManager.disable()
            statusItemController?.setRunAtStartupEnabled(result.state.enabled)

            if result.shouldTerminateCurrentProcess {
                if enabled {
                    NSApp.terminate(nil)
                } else {
                    NSApp.terminate(nil)
                }
            }
        } catch {
            statusItemController?.setRunAtStartupEnabled(launchAgentManager.currentState().enabled)
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    private func presentErrorAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "MacInputSourceLock"
        alert.informativeText = message
        alert.runModal()
    }
}

@main
@MainActor
struct MacInputSourceLockApp {
    static func main() {
        do {
            let configuration = try Configuration.parse(arguments: CommandLine.arguments)
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)

            let delegate = AppDelegate(configuration: configuration)
            application.delegate = delegate
            application.run()
        } catch let error as ConfigurationError {
            let stream = error.exitCode == 0 ? stdout : stderr
            fputs("\(error.localizedDescription)\n", stream)
            exit(error.exitCode)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
