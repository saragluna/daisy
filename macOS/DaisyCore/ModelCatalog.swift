import Foundation

public enum ModelCatalog {
    public static let modelsURL = URL(string: "http://127.0.0.1:4141/v1/models?limit=1000")!

    public static func models(from responseData: Data) throws -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let data = root["data"] as? [Any] else {
            throw DaisyCoreError.invalidModelsResponse
        }

        let models = data.compactMap { item -> String? in
            guard let object = item as? [String: Any], let id = object["id"] as? String else {
                return nil
            }
            let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }
        return sorted(models)
    }

    public static func sorted(_ models: [String]) -> [String] {
        Array(Set(models.filter { !$0.isEmpty })).sorted { lhs, rhs in
            let lhsKey = (rank(lhs), lhs.lowercased(), lhs)
            let rhsKey = (rank(rhs), rhs.lowercased(), rhs)
            if lhsKey.0 != rhsKey.0 { return lhsKey.0 < rhsKey.0 }
            if lhsKey.1 != rhsKey.1 { return lhsKey.1 < rhsKey.1 }
            return lhsKey.2 < rhsKey.2
        }
    }

    public static func filtered(_ models: [String], matching query: String) -> [String] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return models }
        return models.filter { $0.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    private static func rank(_ model: String) -> Int {
        let lowered = model.lowercased()
        if lowered.hasPrefix("gpt") { return 0 }
        if lowered.hasPrefix("claude") { return 1 }
        return 2
    }
}
