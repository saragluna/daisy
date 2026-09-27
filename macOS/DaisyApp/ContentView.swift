import SwiftUI
import DaisyCore

enum NavigationItem: String, CaseIterable, Identifiable {
    case services = "Services"
    case models = "Models"
    case config = "Config"
    case logs = "Logs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .services: return "switch.2"
        case .models: return "cpu"
        case .logs: return "doc.text"
        case .config: return "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var logManager: LogManager

    @State private var selectedItem: NavigationItem = .services
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(NavigationItem.allCases, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .safeAreaInset(edge: .bottom) {
                ServicesSummaryBadge()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        } detail: {
            Group {
                switch selectedItem {
                case .services:
                    ServicesView()
                case .models:
                    ModelsView()
                case .logs:
                    LogsView()
                case .config:
                    ConfigView()
                }
            }
            .navigationTitle("Daisy")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {}
    }
}

struct ServicesSummaryBadge: View {
    @EnvironmentObject var serviceManager: ServiceManager

    private var runningCount: Int {
        serviceManager.services.filter(\.isRunning).count
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(runningCount == serviceManager.services.count ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text("\(runningCount)/\(serviceManager.services.count) running")
                .font(.caption)
                .fontWeight(.medium)

            Spacer()
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ServicesView: View {
    @EnvironmentObject var serviceManager: ServiceManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(serviceManager.services) { service in
                    ServiceCard(service: service)
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ServiceCard: View {
    @EnvironmentObject var serviceManager: ServiceManager
    let service: ManagedServiceState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: service.id.systemImage)
                    .font(.title2)
                    .foregroundStyle(service.isRunning ? .green : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(service.id.displayName)
                        .font(.headline)

                    Text(service.id.endpoint)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)

                }

                Spacer()

                StatusPill(isRunning: service.isRunning, text: service.statusText)
            }

            if let error = service.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    service.isRunning ? serviceManager.stop(service.id) : serviceManager.start(service.id)
                } label: {
                    Label(service.isRunning ? "Stop" : "Start", systemImage: service.isRunning ? "stop.fill" : "play.fill")
                }

                Button {
                    serviceManager.restart(service.id)
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .disabled(!service.isRunning)

                Spacer()
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusPill: View {
    let isRunning: Bool
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

struct ModelsView: View {
    @EnvironmentObject var logManager: LogManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var searchText = ""
    @State private var hoveredModel: String?
    @State private var message: String?
    @State private var modelPendingAddition: String?
    @State private var customModelName = ""
    @State private var isShowingAddModelDialog = false

    private var filteredModels: [String] {
        ModelCatalog.filtered(logManager.availableModels, matching: searchText)
    }

    var body: some View {
        Group {
            if logManager.availableModels.isEmpty && logManager.isLoadingModels {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Refreshing models...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if logManager.availableModels.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Models Cached")
                        .font(.title3)
                        .fontWeight(.medium)
                    Button {
                        logManager.refreshModelsFromAPI()
                    } label: {
                        Label("Refresh Models", systemImage: "arrow.clockwise")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(filteredModels, id: \.self) { model in
                            let isConfigured = settingsManager.isModelInLiteLLMConfig(model)

                            HStack {
                                Image(systemName: modelIcon(for: model))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(model)
                                    .font(.system(.body, design: .monospaced))

                                Spacer()

                                if hoveredModel == model {
                                    if isConfigured {
                                        Button(role: .destructive) {
                                            removeModelFromLiteLLM(model)
                                        } label: {
                                            Label("Remove", systemImage: "minus.circle")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.borderless)
                                    } else {
                                        Button {
                                            modelPendingAddition = model
                                            customModelName = model
                                            isShowingAddModelDialog = true
                                        } label: {
                                            Label("Add to LiteLLM", systemImage: "plus.circle")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                } else if isConfigured {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                            }
                            .onHover { isHovered in
                                hoveredModel = isHovered ? model : nil
                            }
                        }
                    } header: {
                        Text("\(filteredModels.count) model\(filteredModels.count == 1 ? "" : "s") available")
                    }
                }
                .searchable(text: $searchText, placement: .toolbar, prompt: "Filter models")
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    logManager.refreshModelsFromAPI()
                } label: {
                    Label("Refresh Models", systemImage: "arrow.clockwise")
                }
                .disabled(logManager.isLoadingModels)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            if let message {
                HStack {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        self.message = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .alert("Add to LiteLLM", isPresented: $isShowingAddModelDialog) {
            TextField("Model name", text: $customModelName)

            Button("Cancel", role: .cancel) {
                modelPendingAddition = nil
            }

            Button("Add") {
                addPendingModelToLiteLLM()
            }
            .disabled(customModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            if let model = modelPendingAddition {
                Text("Choose the name clients will use for \(model).")
            }
        }
    }

    private func addPendingModelToLiteLLM() {
        guard let model = modelPendingAddition else { return }

        do {
            let name = customModelName.trimmingCharacters(in: .whitespacesAndNewlines)
            try settingsManager.addModelToLiteLLMConfig(model, modelName: name)
            message = "Added \(model) as \(name). Restart LiteLLM Proxy to apply."
        } catch {
            message = error.localizedDescription
        }

        modelPendingAddition = nil
    }

    private func removeModelFromLiteLLM(_ model: String) {
        do {
            try settingsManager.removeModelFromLiteLLMConfig(model)
            message = "Removed \(model). Restart LiteLLM Proxy to apply."
        } catch {
            message = error.localizedDescription
        }
    }

    private func modelIcon(for model: String) -> String {
        let lowercasedModel = model.lowercased()
        if lowercasedModel.contains("claude") { return "brain" }
        if lowercasedModel.contains("gpt") { return "bubble.left" }
        if lowercasedModel.contains("gemini") { return "sparkles" }
        if lowercasedModel.contains("embedding") { return "square.grid.3x3" }
        return "cpu"
    }
}

struct LogsView: View {
    @EnvironmentObject var logManager: LogManager
    @State private var autoScroll = true
    @State private var searchText = ""
    @State private var selectedService: ServiceID? = nil

    private var currentLines: [String] {
        logManager.logLines(for: selectedService)
    }

    private var filteredLines: [String] {
        guard !searchText.isEmpty else { return currentLines }
        return currentLines.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if filteredLines.isEmpty {
                            Text("No logs yet...")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(filteredLines.enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("logBottom")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                }
                .onChange(of: logManager.logLines.count) { _, _ in
                    if autoScroll {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack(spacing: 16) {
                Picker("", selection: $selectedService) {
                    Text("All").tag(ServiceID?.none)
                    ForEach(ServiceID.allCases) { service in
                        Text(service.displayName).tag(ServiceID?.some(service))
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)

                Spacer()

                Text("\(currentLines.count) lines")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Button(role: .destructive) {
                    logManager.clearLogs()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter logs")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ConfigView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var tokenInput = ""
    @State private var tokenVisible = false
    @State private var liteLLMConfigInput = ""
    @State private var liteLLMVersionInput = ""
    @State private var claudeSettingsInput = ""
    @State private var message: String?

    private var claudeSettingsValidationError: String? {
        guard !claudeSettingsInput.isEmpty else { return nil }
        return SettingsManager.validateJSON(claudeSettingsInput)
    }

    private var isClaudeSettingsChanged: Bool {
        claudeSettingsInput != settingsManager.claudeSettings
    }

    private var liteLLMVersionValidationError: String? {
        SettingsManager.validateLiteLLMVersion(
            liteLLMVersionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("copilot-api")
                        .font(.headline)

                    HStack(spacing: 6) {
                        if tokenVisible {
                            TextField("GitHub token", text: $tokenInput)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("GitHub token", text: $tokenInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            tokenVisible.toggle()
                        } label: {
                            Image(systemName: tokenVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(tokenVisible ? "Hide Token" : "Show Token")
                    }

                    HStack {
                        Text("Stored securely in macOS Keychain")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            settingsManager.startDeviceFlow()
                        } label: {
                            Label("Get Copilot Token", systemImage: "person.badge.key")
                        }
                        .disabled(settingsManager.isDeviceFlowActive)

                        Button {
                            serviceManager.restart(.copilotAPI)
                        } label: {
                            Label("Restart", systemImage: "arrow.clockwise")
                        }
                        .disabled(!serviceManager.state(for: .copilotAPI).isRunning)
                        .help("Restart copilot-api")

                        Button {
                            saveToken()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .disabled(tokenInput == settingsManager.token)
                        .help("Save Token")
                    }

                    if settingsManager.isDeviceFlowActive, let code = settingsManager.deviceFlowUserCode {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Enter code:")
                                .font(.callout)
                            Text(code)
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.bold)
                                .textSelection(.enabled)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy Code")

                            Spacer()

                            Button("Cancel") {
                                settingsManager.cancelDeviceFlow()
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    } else if settingsManager.isDeviceFlowActive {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Starting device flow...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = settingsManager.deviceFlowError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 10) {
                    Text("LiteLLM Proxy")
                        .font(.headline)

                    HStack {
                        Text("Version")
                            .foregroundStyle(.secondary)

                        TextField(SettingsManager.defaultLiteLLMVersion, text: $liteLLMVersionInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)

                        Button {
                            saveLiteLLMVersion()
                        } label: {
                            Label("Save Version", systemImage: "square.and.arrow.down")
                        }
                        .disabled(
                            liteLLMVersionInput.trimmingCharacters(in: .whitespacesAndNewlines) == settingsManager.liteLLMVersion
                                || liteLLMVersionValidationError != nil
                        )

                        Spacer()

                        Text("Installed: \(settingsManager.installedLiteLLMVersion ?? "Not installed")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            settingsManager.refreshInstalledLiteLLMVersion()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh installed version")
                    }

                    if let error = liteLLMVersionValidationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    TextEditor(text: $liteLLMConfigInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 220)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2))
                        }

                    HStack {
                        Text("Application Support/litellm-config.yaml")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            serviceManager.restart(.liteLLMProxy)
                        } label: {
                            Label("Restart", systemImage: "arrow.clockwise")
                        }
                        .disabled(!serviceManager.state(for: .liteLLMProxy).isRunning)
                        .help("Restart LiteLLM Proxy")

                        Button {
                            saveLiteLLMConfig()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .disabled(liteLLMConfigInput == settingsManager.liteLLMConfig)
                        .help("Save Config")
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                // Claude Code Settings
                VStack(alignment: .leading, spacing: 10) {
                    Text("Claude Code")
                        .font(.headline)

                    SyntaxHighlightedTextEditor(text: $claudeSettingsInput)
                        .frame(minHeight: 260)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(claudeSettingsValidationError != nil ? Color.red.opacity(0.6) : Color.secondary.opacity(0.2))
                        }

                    if let error = claudeSettingsValidationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Text("~/.claude/settings.json")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            formatClaudeSettings()
                        } label: {
                            Label("Format", systemImage: "text.alignleft")
                        }
                        .disabled(claudeSettingsValidationError != nil)
                        .help("Pretty-print JSON")

                        Button {
                            saveClaudeSettings()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .disabled(!isClaudeSettingsChanged || claudeSettingsValidationError != nil)
                        .help("Save Settings")
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .onAppear {
            tokenInput = settingsManager.token
            settingsManager.loadLiteLLMConfig()
            liteLLMConfigInput = settingsManager.liteLLMConfig
            settingsManager.loadLiteLLMVersion()
            liteLLMVersionInput = settingsManager.liteLLMVersion
            settingsManager.refreshInstalledLiteLLMVersion()
            settingsManager.loadClaudeSettings()
            claudeSettingsInput = settingsManager.claudeSettings
        }
        .onChange(of: settingsManager.token) { _, newValue in
            tokenInput = newValue
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func saveToken() {
        do {
            try settingsManager.saveToken(tokenInput)
            message = "Token saved. Restart copilot-api to apply it."
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveLiteLLMConfig() {
        do {
            try settingsManager.saveLiteLLMConfig(liteLLMConfigInput)
            message = "LiteLLM config saved. Restart LiteLLM Proxy to apply it."
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveLiteLLMVersion() {
        do {
            try settingsManager.saveLiteLLMVersion(liteLLMVersionInput)
            liteLLMVersionInput = settingsManager.liteLLMVersion
            message = "LiteLLM version \(settingsManager.liteLLMVersion) saved. Restart LiteLLM Proxy to install it."
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveClaudeSettings() {
        do {
            try settingsManager.saveClaudeSettings(claudeSettingsInput)
            claudeSettingsInput = settingsManager.claudeSettings
            message = "Claude Code settings saved."
        } catch {
            message = error.localizedDescription
        }
    }

    private func formatClaudeSettings() {
        if let formatted = settingsManager.formatClaudeSettings(claudeSettingsInput) {
            claudeSettingsInput = formatted
        }
    }
}
