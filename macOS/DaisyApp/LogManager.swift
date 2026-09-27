import Foundation
import DaisyCore

final class LogManager: ObservableObject {
    static let shared = LogManager()

    @Published var logs: String = ""
    @Published var logLines: [String] = []
    @Published var serviceLogLines: [ServiceID: [String]] = [:]
    @Published var availableModels: [String] = []
    @Published var isLoadingModels = false

    private let modelsURL = ModelCatalog.modelsURL
    private let modelsCacheKey = "Daisy.cachedModels"
    private let maxLogLines = 5_000

    private init() {
        loadCachedModels()
    }

    func append(service: ServiceID, stream: String, content: String) {
        let newLines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "[\(stream)] \(String($0))" }

        // Per-service logs
        var lines = serviceLogLines[service, default: []]
        lines.append(contentsOf: newLines)
        if lines.count > maxLogLines {
            lines.removeFirst(lines.count - maxLogLines)
        }
        serviceLogLines[service] = lines

        // Combined logs (with service prefix)
        let combinedLines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "[\(service.displayName)][\(stream)] \(String($0))" }
        logLines.append(contentsOf: combinedLines)
        if logLines.count > maxLogLines {
            logLines.removeFirst(logLines.count - maxLogLines)
        }
        logs = logLines.joined(separator: "\n")
    }

    func clearLogs() {
        logs = ""
        logLines = []
        serviceLogLines = [:]
    }

    func logLines(for filter: ServiceID?) -> [String] {
        guard let filter else { return logLines }
        return serviceLogLines[filter, default: []]
    }

    func refreshModelsFromAPI(retryCount: Int = 2) {
        isLoadingModels = true

        URLSession.shared.dataTask(with: modelsURL) { [weak self] data, _, error in
            guard let self else { return }

            if let data,
               error == nil,
               let models = try? ModelCatalog.models(from: data) {

                DispatchQueue.main.async {
                    self.isLoadingModels = false
                    self.updateModels(models, cache: true)
                }
                return
            }

            if retryCount > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.refreshModelsFromAPI(retryCount: retryCount - 1)
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingModels = false
                }
            }
        }.resume()
    }

    private func loadCachedModels() {
        let cachedModels = UserDefaults.standard.stringArray(forKey: modelsCacheKey) ?? []
        updateModels(cachedModels, cache: false)
    }

    private func updateModels(_ models: [String], cache: Bool) {
        let sortedModels = ModelCatalog.sorted(models)

        if sortedModels != availableModels {
            availableModels = sortedModels
        }

        if cache && !sortedModels.isEmpty {
            UserDefaults.standard.set(sortedModels, forKey: modelsCacheKey)
        }
    }

}
