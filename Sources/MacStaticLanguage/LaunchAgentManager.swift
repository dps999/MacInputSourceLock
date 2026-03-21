import Foundation

enum LaunchAgentError: Error, LocalizedError {
    case invalidExecutablePath
    case plistEncodingFailed
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidExecutablePath:
            return "Could not determine the executable path for the startup item."
        case .plistEncodingFailed:
            return "Could not encode the LaunchAgent plist."
        case let .commandFailed(message):
            return message
        }
    }
}

struct LaunchAgentState {
    let enabled: Bool
    let loaded: Bool
}

struct LaunchAgentToggleResult {
    let state: LaunchAgentState
    let shouldTerminateCurrentProcess: Bool
}

final class LaunchAgentManager {
    static let agentLabel = "com.macstaticlanguage.agent"

    private let configuration: Configuration
    private let executableURL: URL
    private let fileManager = FileManager.default

    init(configuration: Configuration, executableURL: URL?) throws {
        guard let executableURL, executableURL.isFileURL else {
            throw LaunchAgentError.invalidExecutablePath
        }

        self.configuration = configuration
        self.executableURL = executableURL
    }

    func currentState() -> LaunchAgentState {
        LaunchAgentState(
            enabled: fileManager.fileExists(atPath: plistURL.path),
            loaded: isLoaded()
        )
    }

    func enable() throws -> LaunchAgentToggleResult {
        try createDirectoriesIfNeeded()
        try writePlist()

        let stateBeforeBootstrap = currentState()
        let shouldTerminateCurrentProcess: Bool

        if isCurrentProcessManagedByLaunchAgent {
            shouldTerminateCurrentProcess = false
        } else if stateBeforeBootstrap.loaded {
            shouldTerminateCurrentProcess = true
        } else {
            _ = try runLaunchctl(["bootout", serviceTarget], allowFailure: true)
            _ = try runLaunchctl(["bootstrap", domainTarget, plistURL.path])
            _ = try runLaunchctl(["kickstart", "-k", serviceTarget], allowFailure: true)
            shouldTerminateCurrentProcess = true
        }

        return LaunchAgentToggleResult(
            state: currentState(),
            shouldTerminateCurrentProcess: shouldTerminateCurrentProcess
        )
    }

    func disable() throws -> LaunchAgentToggleResult {
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }

        if isLoaded() {
            _ = try runLaunchctl(["bootout", serviceTarget], allowFailure: true)
        }

        return LaunchAgentToggleResult(
            state: currentState(),
            shouldTerminateCurrentProcess: isCurrentProcessManagedByLaunchAgent
        )
    }

    private var isCurrentProcessManagedByLaunchAgent: Bool {
        ProcessInfo.processInfo.environment["MACSTATICLANGUAGE_LAUNCHED_BY_AGENT"] == "1"
    }

    private var launchAgentsDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private var logsDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacStaticLanguage", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectoryURL.appendingPathComponent("\(Self.agentLabel).plist")
    }

    private var stdoutLogURL: URL {
        logsDirectoryURL.appendingPathComponent("stdout.log")
    }

    private var stderrLogURL: URL {
        logsDirectoryURL.appendingPathComponent("stderr.log")
    }

    private var domainTarget: String {
        "gui/\(getuid())"
    }

    private var serviceTarget: String {
        "\(domainTarget)/\(Self.agentLabel)"
    }

    private func createDirectoriesIfNeeded() throws {
        try fileManager.createDirectory(at: launchAgentsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
    }

    private func writePlist() throws {
        var environmentVariables: [String: String] = [
            "MACSTATICLANGUAGE_INPUT_SOURCE_ID": configuration.inputSourceID,
            "MACSTATICLANGUAGE_POLL_INTERVAL": String(configuration.pollInterval),
            "MACSTATICLANGUAGE_LAUNCHED_BY_AGENT": "1",
        ]

        if !configuration.promptForAccessibility {
            environmentVariables["MACSTATICLANGUAGE_NO_ACCESSIBILITY_PROMPT"] = "1"
        }

        let plist: [String: Any] = [
            "Label": Self.agentLabel,
            "ProgramArguments": [executableURL.path],
            "EnvironmentVariables": environmentVariables,
            "RunAtLoad": true,
            "KeepAlive": true,
            "LimitLoadToSessionType": ["Aqua"],
            "StandardOutPath": stdoutLogURL.path,
            "StandardErrorPath": stderrLogURL.path,
        ]

        guard PropertyListSerialization.propertyList(plist, isValidFor: .xml) else {
            throw LaunchAgentError.plistEncodingFailed
        }

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    private func isLoaded() -> Bool {
        do {
            _ = try runLaunchctl(["print", serviceTarget])
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 || allowFailure {
            return stdout.isEmpty ? stderr : stdout
        }

        let command = (["/bin/launchctl"] + arguments).joined(separator: " ")
        let details = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        throw LaunchAgentError.commandFailed(details.isEmpty ? "Command failed: \(command)" : "Command failed: \(command)\n\(details)")
    }
}
