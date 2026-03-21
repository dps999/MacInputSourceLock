import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configuration: Configuration
    private var enforcer: LanguageEnforcer?

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforcer = LanguageEnforcer(configuration: configuration)
        enforcer?.start()
    }
}

@main
@MainActor
struct MacStaticLanguageApp {
    static func main() {
        do {
            let configuration = try Configuration.parse(arguments: CommandLine.arguments)
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)

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
