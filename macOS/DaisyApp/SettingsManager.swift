import Foundation
import ServiceManagement
import AppKit
import DaisyCore

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    static let defaultLiteLLMVersion = "1.101.0"

    @Published var token: String = ""
    @Published var openAtLogin: Bool = false
    @Published var liteLLMConfig: String = ""
    @Published var liteLLMVersion: String = ""
    @Published private(set) var installedLiteLLMVersion: String?
    @Published var claudeSettings: String = ""
    @Published var deviceFlowUserCode: String?
    @Published var isDeviceFlowActive: Bool = false
    @Published var deviceFlowError: String?

    private var deviceFlowTask: Task<Void, Never>?
    private let credentialStore = CredentialStore(service: "com.daisy.Daisy", account: "github-token")

    static let appSupportDir: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.daisy.Daisy")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }()

    private let envPath = SettingsManager.appSupportDir.appendingPathComponent("copilot-api.env")
    private let liteLLMConfigPath = SettingsManager.appSupportDir.appendingPathComponent("litellm-config.yaml")
    private let liteLLMVersionPath = SettingsManager.appSupportDir.appendingPathComponent("litellm-version.txt")
    private let claudeSettingsPath: URL = {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        return claudeDir.appendingPathComponent("settings.json")
    }()

    private let legacyEnvPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/copilot-api/.env")
    private let legacyLiteLLMConfigPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Projects/litellm-proxy/config.yaml")
    private let legacyAppSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("com.daisy.CopilotAPIManager")

    init() {
        migrateIfNeeded()
        loadToken()
        loadLiteLLMConfig()
        loadLiteLLMVersion()
        refreshInstalledLiteLLMVersion()
        loadClaudeSettings()
        checkLoginItem()
    }

    private func migrateIfNeeded() {
        let fm = FileManager.default
        let legacyEnvInAppSupport = legacyAppSupportDir.appendingPathComponent("copilot-api.env")
        let legacyConfigInAppSupport = legacyAppSupportDir.appendingPathComponent("litellm-config.yaml")
        if fm.fileExists(atPath: legacyConfigInAppSupport.path) && !fm.fileExists(atPath: liteLLMConfigPath.path) {
            try? fm.copyItem(at: legacyConfigInAppSupport, to: liteLLMConfigPath)
        }
        if fm.fileExists(atPath: legacyLiteLLMConfigPath.path) && !fm.fileExists(atPath: liteLLMConfigPath.path) {
            try? fm.copyItem(at: legacyLiteLLMConfigPath, to: liteLLMConfigPath)
        }

        do {
            if try credentialStore.read()?.isEmpty != false {
                for path in [envPath, legacyEnvInAppSupport, legacyEnvPath] {
                    guard let content = try? String(contentsOf: path, encoding: .utf8),
                          case let migratedToken = ConfigurationRules.token(fromEnvironment: content),
                          !migratedToken.isEmpty else {
                        continue
                    }
                    try credentialStore.write(migratedToken)
                    break
                }
            }

            // These files belong to Daisy. The original ~/.config file may still be
            // used by another copilot-api installation, so it is left in place.
            try? fm.removeItem(at: envPath)
            try? fm.removeItem(at: legacyEnvInAppSupport)
        } catch {
            print("Failed to migrate token to Keychain: \(error)")
        }

        secureFileIfPresent(liteLLMConfigPath)
        secureFileIfPresent(liteLLMVersionPath)
        secureFileIfPresent(claudeSettingsPath)
    }

    func loadToken() {
        do {
            token = try credentialStore.read() ?? ""
        } catch {
            token = ""
            print("Failed to load token from Keychain: \(error)")
        }
    }

    func saveToken(_ newToken: String) throws {
        let normalized = try ConfigurationRules.normalizeToken(newToken)
        try credentialStore.write(normalized)
        try? FileManager.default.removeItem(at: envPath)
        token = normalized
    }

    func loadLiteLLMConfig() {
        do {
            liteLLMConfig = try String(contentsOf: liteLLMConfigPath, encoding: .utf8)
        } catch {
            liteLLMConfig = ""
            print("Failed to load LiteLLM config: \(error)")
        }
    }

    func saveLiteLLMConfig(_ config: String) throws {
        try config.write(to: liteLLMConfigPath, atomically: true, encoding: .utf8)
        try secureFile(liteLLMConfigPath)
        liteLLMConfig = config
    }

    func loadLiteLLMVersion() {
        guard let value = try? String(contentsOf: liteLLMVersionPath, encoding: .utf8) else {
            liteLLMVersion = Self.defaultLiteLLMVersion
            return
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        liteLLMVersion = normalized.isEmpty || normalized.lowercased() == "latest"
            ? Self.defaultLiteLLMVersion
            : normalized
    }

    func saveLiteLLMVersion(_ version: String) throws {
        let normalized = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationError = Self.validateLiteLLMVersion(normalized) {
            throw NSError(
                domain: "Daisy",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: validationError]
            )
        }

        try normalized.write(to: liteLLMVersionPath, atomically: true, encoding: .utf8)
        try secureFile(liteLLMVersionPath)
        liteLLMVersion = normalized
    }

    static func validateLiteLLMVersion(_ version: String) -> String? {
        ConfigurationRules.validateLiteLLMVersion(version)
    }

    func refreshInstalledLiteLLMVersion() {
        let pythonURL = SettingsManager.appSupportDir
            .appendingPathComponent("litellm-venv/bin/python")

        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            installedLiteLLMVersion = nil
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = pythonURL
            process.arguments = [
                "-c",
                "import importlib.metadata; print(importlib.metadata.version('litellm'))"
            ]
            process.standardOutput = output
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                DispatchQueue.main.async {
                    self.installedLiteLLMVersion = process.terminationStatus == 0 && value?.isEmpty == false
                        ? value
                        : nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.installedLiteLLMVersion = nil
                }
            }
        }
    }

    // MARK: - Claude Code Settings (~/.claude/settings.json)

    func loadClaudeSettings() {
        guard FileManager.default.fileExists(atPath: claudeSettingsPath.path) else {
            claudeSettings = "{}"
            return
        }
        do {
            let raw = try String(contentsOf: claudeSettingsPath, encoding: .utf8)
            claudeSettings = (try? ConfigurationRules.canonicalJSONObject(raw)) ?? raw
        } catch {
            claudeSettings = "{}"
            print("Failed to load Claude settings: \(error)")
        }
    }

    func saveClaudeSettings(_ json: String) throws {
        let formatted = try ConfigurationRules.canonicalJSONObject(json)
        try formatted.write(to: claudeSettingsPath, atomically: true, encoding: .utf8)
        try secureFile(claudeSettingsPath)
        claudeSettings = formatted
    }

    private func secureFileIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? secureFile(url)
    }

    private func secureFile(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func validateJSON(_ text: String) -> String? {
        ConfigurationRules.validateJSONObject(text)
    }

    func formatClaudeSettings(_ json: String) -> String? {
        try? ConfigurationRules.canonicalJSONObject(json)
    }

    func isModelInLiteLLMConfig(_ modelID: String) -> Bool {
        LiteLLMConfigEditor.containsModel(modelID, in: liteLLMConfig)
    }

    func addModelToLiteLLMConfig(_ modelID: String, modelName: String) throws {
        let result = try LiteLLMConfigEditor.addingModel(modelID, named: modelName, to: liteLLMConfig)
        guard result != liteLLMConfig else { return }
        try saveLiteLLMConfig(result)
    }

    func removeModelFromLiteLLMConfig(_ modelID: String) throws {
        let result = try LiteLLMConfigEditor.removingModel(modelID, from: liteLLMConfig)
        guard result != liteLLMConfig else { return }
        try saveLiteLLMConfig(result)
    }

    func checkLoginItem() {
        if #available(macOS 13.0, *) {
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func setOpenAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                openAtLogin = enabled
            } catch {
                print("Failed to set login item: \(error)")
            }
        }
    }

    // MARK: - GitHub Device Flow

    func startDeviceFlow() {
        deviceFlowTask?.cancel()
        deviceFlowError = nil
        isDeviceFlowActive = true
        deviceFlowUserCode = nil

        deviceFlowTask = Task { @MainActor in
            do {
                // Step 1: Request device code
                var request = URLRequest(url: GitHubDeviceFlowProtocol.deviceCodeURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: GitHubDeviceFlowProtocol.beginRequestPayload
                )

                let (data, _) = try await URLSession.shared.data(for: request)
                let session = try GitHubDeviceFlowProtocol.session(from: data)

                deviceFlowUserCode = session.userCode

                // Open browser
                NSWorkspace.shared.open(session.verificationURL)

                // Step 2: Poll for token
                var pollIntervalSeconds = session.pollIntervalSeconds
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds) * 1_000_000_000)

                    var pollReq = URLRequest(url: GitHubDeviceFlowProtocol.accessTokenURL)
                    pollReq.httpMethod = "POST"
                    pollReq.setValue("application/json", forHTTPHeaderField: "Accept")
                    pollReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    pollReq.httpBody = try JSONSerialization.data(
                        withJSONObject: GitHubDeviceFlowProtocol.pollRequestPayload(deviceCode: session.deviceCode)
                    )

                    let (pollData, _) = try await URLSession.shared.data(for: pollReq)
                    switch try GitHubDeviceFlowProtocol.pollResult(from: pollData) {
                    case let .token(accessToken):
                        try saveToken(accessToken)
                        deviceFlowUserCode = nil
                        isDeviceFlowActive = false
                        return
                    case .pending:
                        continue
                    case .slowDown:
                        pollIntervalSeconds += GitHubDeviceFlowProtocol.slowDownIncrementSeconds
                    case let .failure(message):
                        deviceFlowError = message
                        isDeviceFlowActive = false
                        deviceFlowUserCode = nil
                        return
                    }
                }
            } catch is CancellationError {
                // cancelled
            } catch {
                deviceFlowError = error.localizedDescription
            }
            isDeviceFlowActive = false
            deviceFlowUserCode = nil
        }
    }

    func cancelDeviceFlow() {
        deviceFlowTask?.cancel()
        isDeviceFlowActive = false
        deviceFlowUserCode = nil
        deviceFlowError = nil
    }
}
