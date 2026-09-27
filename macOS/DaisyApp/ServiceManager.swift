import Foundation

enum ServiceID: String, CaseIterable, Identifiable {
    case copilotAPI
    case liteLLMProxy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copilotAPI: return "copilot-api"
        case .liteLLMProxy: return "LiteLLM Proxy"
        }
    }

    var endpoint: String {
        switch self {
        case .copilotAPI: return "http://localhost:4141"
        case .liteLLMProxy: return "http://localhost:4000"
        }
    }

    var configPath: String {
        let dir = SettingsManager.appSupportDir.path
        switch self {
        case .copilotAPI: return "macOS Keychain"
        case .liteLLMProxy: return "\(dir)/litellm-config.yaml"
        }
    }

    var systemImage: String {
        switch self {
        case .copilotAPI: return "sparkles"
        case .liteLLMProxy: return "point.3.connected.trianglepath.dotted"
        }
    }

    var port: Int {
        switch self {
        case .copilotAPI: return 4141
        case .liteLLMProxy: return 4000
        }
    }
}

struct ManagedServiceState: Identifiable {
    let id: ServiceID
    var isRunning = false
    var statusText = "Stopped"
    var lastError: String?
}

final class ServiceManager: ObservableObject {
    static let shared = ServiceManager()

    @Published private(set) var services: [ManagedServiceState] = ServiceID.allCases.map {
        ManagedServiceState(id: $0)
    }

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let processQueue = DispatchQueue(label: "Daisy.ServiceManager")
    private var processes: [ServiceID: Process] = [:]

    private var copilotRuntimePath: URL {
        SettingsManager.appSupportDir.appendingPathComponent("copilot-runtime")
    }

    private var copilotRuntimeMainPath: URL {
        copilotRuntimePath.appendingPathComponent("node_modules/copilot-api/dist/main.js")
    }

    private var copilotRuntimeMarkerPath: URL {
        copilotRuntimePath.appendingPathComponent(".installed-version")
    }

    private var liteLLMConfigPath: URL {
        SettingsManager.appSupportDir.appendingPathComponent("litellm-config.yaml")
    }

    private var liteLLMVenvPath: URL {
        SettingsManager.appSupportDir.appendingPathComponent("litellm-venv")
    }

    private var liteLLMRuntimeMarkerPath: URL {
        liteLLMVenvPath.appendingPathComponent(".daisy-managed-runtime")
    }

    private var legacyCopilotPlistPath: URL {
        home.appendingPathComponent("Library/LaunchAgents/com.copilot-api.plist")
    }

    private init() {
        processQueue.async {
            self.stopLegacyCopilotLaunchd()
        }
    }

    func state(for id: ServiceID) -> ManagedServiceState {
        services.first { $0.id == id } ?? ManagedServiceState(id: id)
    }

    func start(_ id: ServiceID) {
        processQueue.async { [self] in
            guard self.processes[id]?.isRunning != true else { return }

            do {
                try self.ensurePortIsAvailable(id)
                if id == .copilotAPI {
                    self.stopLegacyCopilotLaunchd()
                }

                let process = try self.makeProcess(for: id)
                self.attachOutputPipes(to: process, service: id)
                process.terminationHandler = { [weak self] terminatedProcess in
                    guard let self else { return }
                    self.processQueue.async {
                        guard self.processes[id] === terminatedProcess else { return }
                        self.processes[id] = nil
                        DispatchQueue.main.async {
                            self.updateState(
                                id,
                                isRunning: false,
                                statusText: "Stopped",
                                error: terminatedProcess.terminationStatus == 0 ? nil : "Exited with code \(terminatedProcess.terminationStatus)"
                            )
                        }
                    }
                }

                try process.run()
                self.processes[id] = process

                DispatchQueue.main.async {
                    self.updateState(id, isRunning: true, statusText: "Running", error: nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.updateState(id, isRunning: false, statusText: "Failed", error: error.localizedDescription)
                    LogManager.shared.append(service: id, stream: "error", content: "\(error.localizedDescription)\n")
                }
            }
        }
    }

    func stop(_ id: ServiceID) {
        processQueue.async {
            guard let process = self.processes[id] else {
                DispatchQueue.main.async {
                    self.updateState(id, isRunning: false, statusText: "Stopped", error: nil)
                }
                return
            }

            process.terminate()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if process.isRunning {
                    process.interrupt()
                }
            }
        }
    }

    func restart(_ id: ServiceID) {
        stop(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.start(id)
        }
    }

    func startAll() {
        ServiceID.allCases.forEach { start($0) }
    }

    func stopAll() {
        ServiceID.allCases.forEach { stop($0) }
    }

    private func makeProcess(for id: ServiceID) throws -> Process {
        let process = Process()
        process.currentDirectoryURL = home
        process.environment = processEnvironment()

        switch id {
        case .copilotAPI:
            let token = try copilotToken()
            try ensureCopilotRuntimeInstalled()
            guard let node = findExecutable(named: "node") else {
                throw ServiceError.nodeNotFound
            }
            process.executableURL = node
            process.arguments = [copilotRuntimeMainPath.path, "start"]
            process.environment?["DAISY_GITHUB_TOKEN"] = token
        case .liteLLMProxy:
            try ensureLiteLLMRuntimeInstalled()
            let executable = liteLLMVenvPath.appendingPathComponent("bin/litellm")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw ServiceError.missingLiteLLMRuntime
            }
            process.executableURL = executable
            process.arguments = [
                "--config", liteLLMConfigPath.path,
                "--host", "127.0.0.1",
                "--port", "4000"
            ]
        }

        return process
    }

    private func attachOutputPipes(to process: Process, service: ServiceID) {
        let stdout = Pipe()
        let stderr = Pipe()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let content = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                LogManager.shared.append(service: service, stream: "out", content: content)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let content = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                LogManager.shared.append(service: service, stream: "err", content: content)
            }
        }

        process.standardOutput = stdout
        process.standardError = stderr
    }

    private func copilotToken() throws -> String {
        let token = SettingsManager.shared.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw ServiceError.missingCopilotToken
        }
        return token
    }

    private func ensureCopilotRuntimeInstalled() throws {
        guard let bundledRuntime = Bundle.module.url(forResource: "copilot-runtime", withExtension: nil),
              let desiredVersion = try? String(
                contentsOf: bundledRuntime.appendingPathComponent("runtime-version.txt"),
                encoding: .utf8
              ).trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ServiceError.missingCopilotRuntime
        }

        let installedVersion = try? String(contentsOf: copilotRuntimeMarkerPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if installedVersion == desiredVersion,
           FileManager.default.fileExists(atPath: copilotRuntimeMainPath.path) {
            return
        }

        guard let npm = findExecutable(named: "npm") else {
            throw ServiceError.npmNotFound
        }
        guard let node = findExecutable(named: "node") else {
            throw ServiceError.nodeNotFound
        }

        let fm = FileManager.default
        try fm.createDirectory(at: copilotRuntimePath, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: copilotRuntimePath.path)
        for fileName in ["package.json", "package-lock.json", "patch-copilot-api.mjs", "runtime-version.txt"] {
            let source = bundledRuntime.appendingPathComponent(fileName)
            let destination = copilotRuntimePath.appendingPathComponent(fileName)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
        }

        try runSetupProcess(
            executable: npm,
            arguments: ["ci", "--omit=dev", "--ignore-scripts", "--no-audit", "--no-fund"],
            service: .copilotAPI,
            currentDirectory: copilotRuntimePath
        )
        try runSetupProcess(
            executable: node,
            arguments: [copilotRuntimePath.appendingPathComponent("patch-copilot-api.mjs").path],
            service: .copilotAPI,
            currentDirectory: copilotRuntimePath
        )

        try desiredVersion.write(to: copilotRuntimeMarkerPath, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copilotRuntimeMarkerPath.path)
    }

    private func ensureLiteLLMRuntimeInstalled() throws {
        guard let requirements = Bundle.module.url(
            forResource: "litellm-requirements",
            withExtension: "txt"
        ), let runtimeVersionPath = Bundle.module.url(
            forResource: "litellm-runtime-version",
            withExtension: "txt"
        ), let runtimeVersion = try? String(
            contentsOf: runtimeVersionPath,
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines), !runtimeVersion.isEmpty else {
            throw ServiceError.missingLiteLLMRuntime
        }

        let configuredVersion = SettingsManager.shared.liteLLMVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let version = configuredVersion.isEmpty
            ? SettingsManager.defaultLiteLLMVersion
            : configuredVersion
        let desiredMarker = "\(version)\n\(runtimeVersion)"
        let executable = liteLLMVenvPath.appendingPathComponent("bin/litellm")
        let installedMarker = try? String(
            contentsOf: liteLLMRuntimeMarkerPath,
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if installedMarker == desiredMarker,
           FileManager.default.isExecutableFile(atPath: executable.path) {
            return
        }

        let fm = FileManager.default
        let venvPython = liteLLMVenvPath.appendingPathComponent("bin/python")
        if !fm.isExecutableFile(atPath: venvPython.path) {
            guard let python = findExecutable(named: "python3") else {
                throw ServiceError.pythonNotFound
            }
            try fm.createDirectory(
                at: SettingsManager.appSupportDir,
                withIntermediateDirectories: true
            )
            try runSetupProcess(
                executable: python,
                arguments: ["-m", "venv", liteLLMVenvPath.path],
                service: .liteLLMProxy,
                currentDirectory: SettingsManager.appSupportDir
            )
        }

        try runSetupProcess(
            executable: venvPython,
            arguments: [
                "-m", "pip", "install", "--disable-pip-version-check", "--upgrade",
                "litellm==\(version)", "-r", requirements.path
            ],
            service: .liteLLMProxy,
            currentDirectory: SettingsManager.appSupportDir
        )
        try runSetupProcess(
            executable: venvPython,
            arguments: [
                "-m", "pip", "uninstall", "--yes", "litellm-enterprise"
            ],
            service: .liteLLMProxy,
            currentDirectory: SettingsManager.appSupportDir
        )

        try desiredMarker.write(
            to: liteLLMRuntimeMarkerPath,
            atomically: true,
            encoding: .utf8
        )
        try fm.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: liteLLMRuntimeMarkerPath.path
        )
    }

    private func runSetupProcess(
        executable: URL,
        arguments: [String],
        service: ServiceID,
        currentDirectory: URL
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = processEnvironment()
        process.currentDirectoryURL = currentDirectory
        attachOutputPipes(to: process, service: service)

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ServiceError.setupFailed(executable.lastPathComponent, process.terminationStatus)
        }
    }

    private func findExecutable(named name: String) -> URL? {
        for directory in executableSearchPaths() {
            let candidate = directory.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func executableSearchPaths() -> [URL] {
        var paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)) }
        paths.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            URL(fileURLWithPath: "/usr/bin"),
            URL(fileURLWithPath: "/bin")
        ])

        let nvmVersions = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(
            at: nvmVersions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            paths.append(contentsOf: versions.sorted { $0.lastPathComponent > $1.lastPathComponent }
                .map { $0.appendingPathComponent("bin") })
        }

        var seen = Set<String>()
        return paths.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func stopLegacyCopilotLaunchd() {
        guard FileManager.default.fileExists(atPath: legacyCopilotPlistPath.path) else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", legacyCopilotPlistPath.path]
        try? task.run()
        task.waitUntilExit()
    }

    private func updateState(_ id: ServiceID, isRunning: Bool, statusText: String, error: String?) {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        services[index].isRunning = isRunning
        services[index].statusText = statusText
        services[index].lastError = error
    }

    private func ensurePortIsAvailable(_ id: ServiceID) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-t", "-iTCP:\(id.port)", "-sTCP:LISTEN"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else { return }
        throw ServiceError.portInUse(id.port, id.displayName)
    }

    private func processEnvironment() -> [String: String] {
        let homePath = home.path
        var environment = [
            "HOME": homePath,
            "PATH": executableSearchPaths().map(\.path).joined(separator: ":"),
            "HOST": "127.0.0.1"
        ]
        for key in [
            "LANG", "LC_ALL", "TMPDIR", "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR",
            "NODE_EXTRA_CA_CERTS"
        ] {
            environment[key] = ProcessInfo.processInfo.environment[key]
        }
        return environment
    }
}

enum ServiceError: LocalizedError {
    case missingCopilotToken
    case missingCopilotRuntime
    case missingLiteLLMRuntime
    case nodeNotFound
    case npmNotFound
    case pythonNotFound
    case setupFailed(String, Int32)
    case portInUse(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingCopilotToken:
            return "Missing GitHub token in macOS Keychain"
        case .missingCopilotRuntime:
            return "The bundled copilot-api runtime is missing. Reinstall Daisy."
        case .missingLiteLLMRuntime:
            return "The bundled LiteLLM runtime manifest is missing. Reinstall Daisy."
        case .nodeNotFound:
            return "Node.js was not found. Install Node.js 20.16 or newer."
        case .npmNotFound:
            return "npm was not found. Install Node.js 20.16 or newer."
        case .pythonNotFound:
            return "Python 3.10 through 3.14 was not found. Install Python and add it to PATH."
        case let .setupFailed(command, status):
            return "\(command) failed while preparing the managed runtime (exit \(status))."
        case let .portInUse(port, service):
            return "Port \(port) is already in use. Stop the process using it, then start \(service) again."
        }
    }
}
