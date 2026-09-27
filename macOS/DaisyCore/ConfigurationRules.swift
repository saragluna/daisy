import Foundation

public enum DaisyCoreError: LocalizedError, Equatable {
    case invalidJSON
    case jsonRootMustBeObject
    case invalidLiteLLMVersion
    case emptyModelID
    case emptyModelName
    case modelEntryNotFound
    case invalidModelsResponse
    case invalidDeviceFlowResponse
    case tokenContainsNewline

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Text must be valid JSON."
        case .jsonRootMustBeObject:
            return "Root must be a JSON object ({}), not an array."
        case .invalidLiteLLMVersion:
            return "Enter an exact LiteLLM version, such as 1.101.0."
        case .emptyModelID:
            return "Model ID cannot be empty."
        case .emptyModelName:
            return "Model name cannot be empty."
        case .modelEntryNotFound:
            return "Could not find the LiteLLM model entry to remove."
        case .invalidModelsResponse:
            return "The models response must contain a data array."
        case .invalidDeviceFlowResponse:
            return "GitHub returned an invalid device-flow response."
        case .tokenContainsNewline:
            return "The GitHub token cannot contain a newline."
        }
    }
}

public enum ConfigurationRules {
    public static func normalizeToken(_ token: String) throws -> String {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.contains("\n"), !normalized.contains("\r") else {
            throw DaisyCoreError.tokenContainsNewline
        }
        return normalized
    }

    public static func token(fromEnvironment content: String) -> String {
        let content = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content
        for line in content.components(separatedBy: .newlines) where line.hasPrefix("GITHUB_TOKEN=") {
            return String(line.dropFirst("GITHUB_TOKEN=".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    public static func tokenEnvironment(_ token: String) throws -> String {
        "GITHUB_TOKEN=\(try normalizeToken(token))\n"
    }

    public static func validateLiteLLMVersion(_ version: String) -> String? {
        let pattern = #"^[0-9]+(?:\.[0-9]+)*(?:(?:a|b|rc)[0-9]+)?(?:\.post[0-9]+)?(?:\.dev[0-9]+)?(?:\+[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*)?$"#
        guard version.range(of: pattern, options: .regularExpression) != nil else {
            return DaisyCoreError.invalidLiteLLMVersion.localizedDescription
        }
        return nil
    }

    public static func validateJSONObject(_ text: String) -> String? {
        do {
            _ = try canonicalJSONObject(text)
            return nil
        } catch let error as DaisyCoreError {
            return error.localizedDescription
        } catch {
            return DaisyCoreError.invalidJSON.localizedDescription
        }
    }

    public static func canonicalJSONObject(_ text: String) throws -> String {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw DaisyCoreError.invalidJSON
        }
        guard value is [String: Any] else {
            throw DaisyCoreError.jsonRootMustBeObject
        }
        return try JSONCanonicalRenderer.render(value)
    }
}

private enum JSONCanonicalRenderer {
    static func render(_ value: Any, depth: Int = 0) throws -> String {
        let indentation = String(repeating: "  ", count: depth)
        let nestedIndentation = String(repeating: "  ", count: depth + 1)

        if let object = value as? [String: Any] {
            guard !object.isEmpty else { return "{}" }
            let members = try object.keys.sorted().map { key in
                let encodedKey = try scalar(key)
                let encodedValue = try render(object[key]!, depth: depth + 1)
                return "\(nestedIndentation)\(encodedKey): \(encodedValue)"
            }
            return "{\n\(members.joined(separator: ",\n"))\n\(indentation)}"
        }

        if let array = value as? [Any] {
            guard !array.isEmpty else { return "[]" }
            let elements = try array.map { element in
                "\(nestedIndentation)\(try render(element, depth: depth + 1))"
            }
            return "[\n\(elements.joined(separator: ",\n"))\n\(indentation)]"
        }

        return try scalar(value)
    }

    private static func scalar(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        guard let text = String(data: data, encoding: .utf8) else {
            throw DaisyCoreError.invalidJSON
        }
        return text
    }
}
