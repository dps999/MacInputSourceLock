import Carbon
import Foundation

struct InputSourceDescriptor {
    let id: String
    let name: String
    let isSelected: Bool
}

enum InputSourceError: Error, LocalizedError {
    case notFound(String)
    case selectionFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .notFound(inputSourceID):
            return "Input source not found: \(inputSourceID)"
        case let .selectionFailed(inputSourceID, status):
            return "Failed to select input source \(inputSourceID). OSStatus=\(status)"
        }
    }
}

final class InputSourceManager {
    func listSelectableKeyboardInputSources() -> [InputSourceDescriptor] {
        selectableKeyboardInputSources().compactMap { source in
            guard let id = stringProperty(kTISPropertyInputSourceID, for: source),
                  let name = stringProperty(kTISPropertyLocalizedName, for: source) else {
                return nil
            }

            return InputSourceDescriptor(
                id: id,
                name: name,
                isSelected: boolProperty(kTISPropertyInputSourceIsSelected, for: source) ?? false
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func currentInputSourceID() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return stringProperty(kTISPropertyInputSourceID, for: source)
    }

    func ensureSelected(inputSourceID: String) throws -> Bool {
        if currentInputSourceID() == inputSourceID {
            return false
        }

        guard let source = selectableKeyboardInputSources().first(where: { stringProperty(kTISPropertyInputSourceID, for: $0) == inputSourceID }) else {
            throw InputSourceError.notFound(inputSourceID)
        }

        let status = TISSelectInputSource(source)
        guard status == noErr else {
            throw InputSourceError.selectionFailed(inputSourceID, status)
        }

        return true
    }

    private func selectableKeyboardInputSources() -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsSelectCapable: true,
        ] as CFDictionary

        let list = TISCreateInputSourceList(filter, false).takeRetainedValue() as NSArray
        return list as? [TISInputSource] ?? []
    }

    private func stringProperty(_ key: CFString, for source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    private func boolProperty(_ key: CFString, for source: TISInputSource) -> Bool? {
        guard let value = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        let boolValue = Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue()
        return CFBooleanGetValue(boolValue)
    }
}
