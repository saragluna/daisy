import Foundation

public enum LiteLLMModelMode: String, Equatable {
    case chat
    case embedding
    case responses
}

public enum LiteLLMConfigEditor {
    public static func containsModel(_ modelID: String, in config: String) -> Bool {
        let fullModel = "github_copilot/\(modelID)"
        return normalizedLines(config).contains { yamlModelValue(from: $0) == fullModel }
    }

    public static func mode(for modelID: String) -> LiteLLMModelMode {
        let lowered = modelID.lowercased()
        if lowered.contains("embedding") {
            return .embedding
        }
        if ["codex", "o1", "o3", "o4"].contains(where: lowered.contains) {
            return .responses
        }
        return .chat
    }

    public static func addingModel(
        _ modelID: String,
        named modelName: String,
        to originalConfig: String
    ) throws -> String {
        let normalizedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { throw DaisyCoreError.emptyModelID }
        guard !containsModel(normalizedID, in: originalConfig) else { return originalConfig }

        let normalizedName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw DaisyCoreError.emptyModelName }

        var config = normalizeNewlines(originalConfig)
        if config.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config = "model_list:\n"
        } else {
            config = config.replacingOccurrences(
                of: #"(?m)^(\s*)model_list:\s*\[\s*\]\s*$"#,
                with: "$1model_list:",
                options: .regularExpression
            )
            if !config.hasSuffix("\n") {
                config += "\n"
            }
        }

        var entry = "  - model_name: \(yamlQuotedScalar(normalizedName))\n"
        switch mode(for: normalizedID) {
        case .embedding:
            entry += "    model_info:\n      mode: embedding\n"
        case .responses:
            entry += "    model_info:\n      mode: responses\n"
        case .chat:
            break
        }
        entry += "    litellm_params:\n      model: \(yamlQuotedScalar("github_copilot/\(normalizedID)"))\n"
        return config + entry
    }

    public static func removingModel(_ modelID: String, from originalConfig: String) throws -> String {
        let fullModel = "github_copilot/\(modelID.trimmingCharacters(in: .whitespacesAndNewlines))"
        var lines = normalizedLines(originalConfig)
        var removedEntry = false

        while let modelLineIndex = lines.firstIndex(where: { yamlModelValue(from: $0) == fullModel }) {
            var entryStart: Int?
            for index in stride(from: modelLineIndex, through: 0, by: -1) {
                if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("- model_name:") {
                    entryStart = index
                    break
                }
            }

            guard let entryStart else { throw DaisyCoreError.modelEntryNotFound }
            let entryIndent = leadingWhitespaceCount(in: lines[entryStart])
            var entryEnd = entryStart + 1
            while entryEnd < lines.count {
                let line = lines[entryEnd]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    let indent = leadingWhitespaceCount(in: line)
                    if indent < entryIndent || (indent == entryIndent && trimmed.hasPrefix("- model_name:")) {
                        break
                    }
                }
                entryEnd += 1
            }

            lines.removeSubrange(entryStart..<entryEnd)
            removedEntry = true
        }

        guard removedEntry else { return originalConfig }

        if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- model_name:") }),
           let modelListIndex = lines.firstIndex(where: {
               let value = $0.trimmingCharacters(in: .whitespaces)
               return value == "model_list:" || value == "model_list: []"
           }) {
            let indentation = String(lines[modelListIndex].prefix { $0 == " " || $0 == "\t" })
            lines[modelListIndex] = "\(indentation)model_list: []"
        }

        return lines.joined(separator: "\n")
    }

    private static func normalizeNewlines(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func normalizedLines(_ value: String) -> [String] {
        normalizeNewlines(value).components(separatedBy: "\n")
    }

    private static func yamlModelValue(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("model:") else { return nil }
        var value = String(trimmed.dropFirst("model:".count))
            .trimmingCharacters(in: .whitespaces)
        if value.count >= 2,
           let first = value.first,
           let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }

    private static func leadingWhitespaceCount(in line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func yamlQuotedScalar(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
