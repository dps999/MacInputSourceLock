import Foundation

struct Configuration {
    let inputSourceID: String
    let pollInterval: TimeInterval
    let promptForAccessibility: Bool
    let listInputSources: Bool

    static let defaultInputSourceID = "com.apple.keylayout.ABC"
    static let defaultPollInterval: TimeInterval = 0.5

    static func parse(arguments: [String]) throws -> Configuration {
        var inputSourceID = ProcessInfo.processInfo.environment["MACINPUTSOURCELOCK_INPUT_SOURCE_ID"] ?? defaultInputSourceID
        var pollInterval = defaultPollInterval
        var promptForAccessibility = ProcessInfo.processInfo.environment["MACINPUTSOURCELOCK_NO_ACCESSIBILITY_PROMPT"] != "1"
        var listInputSources = false

        if let environmentPollInterval = ProcessInfo.processInfo.environment["MACINPUTSOURCELOCK_POLL_INTERVAL"] {
            guard let value = Double(environmentPollInterval), value > 0 else {
                throw ConfigurationError.invalidPollInterval(environmentPollInterval)
            }
            pollInterval = value
        }

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--input-source-id":
                index += 1
                guard index < arguments.count else {
                    throw ConfigurationError.missingValue(argument)
                }
                inputSourceID = arguments[index]
            case "--poll-interval":
                index += 1
                guard index < arguments.count else {
                    throw ConfigurationError.missingValue(argument)
                }
                guard let value = Double(arguments[index]), value > 0 else {
                    throw ConfigurationError.invalidPollInterval(arguments[index])
                }
                pollInterval = value
            case "--no-accessibility-prompt":
                promptForAccessibility = false
            case "--list-input-sources":
                listInputSources = true
            case "--help", "-h":
                throw ConfigurationError.helpRequested
            default:
                throw ConfigurationError.unknownArgument(argument)
            }

            index += 1
        }

        return Configuration(
            inputSourceID: inputSourceID,
            pollInterval: pollInterval,
            promptForAccessibility: promptForAccessibility,
            listInputSources: listInputSources
        )
    }
}

enum ConfigurationError: Error, LocalizedError {
    case helpRequested
    case missingValue(String)
    case invalidPollInterval(String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return Self.usage
        case let .missingValue(flag):
            return "Missing value for \(flag).\n\n\(Self.usage)"
        case let .invalidPollInterval(value):
            return "Invalid poll interval: \(value).\n\n\(Self.usage)"
        case let .unknownArgument(argument):
            return "Unknown argument: \(argument).\n\n\(Self.usage)"
        }
    }

    private static let usage = """
    Usage: MacInputSourceLock [options]

      --input-source-id <id>     Keyboard input source to enforce. Default: \(Configuration.defaultInputSourceID)
      --poll-interval <seconds>  Focus polling interval. Default: \(Configuration.defaultPollInterval)
      --list-input-sources       Print available keyboard input source IDs and exit
      --no-accessibility-prompt  Do not open the macOS accessibility permission prompt
      --help, -h                 Show this help
    """

    var exitCode: Int32 {
        switch self {
        case .helpRequested:
            return 0
        case .missingValue, .invalidPollInterval, .unknownArgument:
            return 1
        }
    }
}
