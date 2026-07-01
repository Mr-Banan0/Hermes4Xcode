import SwiftUI

// MARK: - Provider Configuration

struct ProviderConfig: Codable {
    var provider: String = "deepseek"
    var model: String = "deepseek-v4-flash"
    var apiKey: String = ""
    var baseURL: String = "https://api.deepseek.com/v1"
}

let AvailableProviders: [(name: String, defaultModel: String, defaultURL: String)] = [
    ("deepseek", "deepseek-v4-flash", "https://api.deepseek.com/v1"),
    ("openrouter", "deepseek/deepseek-v4-flash", "https://openrouter.ai/api/v1"),
    ("anthropic", "claude-sonnet-4", "https://api.anthropic.com/v1"),
    ("openai", "gpt-4o", "https://api.openai.com/v1"),
    ("google", "gemini-2.0-flash", "https://generativelanguage.googleapis.com/v1beta/openai"),
    ("xai", "grok-3", "https://api.x.ai/v1"),
    ("huggingface", "meta-llama/Llama-3.3-70B-Instruct", "https://router.huggingface.co/hf-inference/v1"),
    ("kimi", "kimi-k2.5", "https://api.moonshot.cn/v1"),
    ("minimax", "minimax-m2.5", "https://api.minimax.io/v1"),
    ("glm", "glm-5", "https://open.bigmodel.cn/api/paas/v4"),
    ("xiaomi", "mimo-v2-flash", "https://api.xiaomimimo.com/v1"),
    ("novita", "deepseek/deepseek-v4-flash", "https://api.novita.ai/v3/openai"),
    ("qwen", "qwen-max", "https://dashscope.aliyuncs.com/compatible-mode/v1"),
    ("ollama", "llama3.2", "http://localhost:11434/v1"),
]

/// Agents that benefit from vision-capable models.
private let visionAgentNames: Set<String> = ["reviewer"]

// MARK: - Provider Settings View

struct ProviderSettingsView: View {
    @ObservedObject var manager: AgentManager
    @State private var config: ProviderConfig
    @State private var selectedProvider = "deepseek"
    @State private var testResult: String?
    @State private var isTesting = false

    /// Agent model overrides — keyed by agent name
    @State private var agentModels: [String: String] = [:]
    @State private var agentProviders: [String: String] = [:]

    private let storageKey = "Hermes4Xcode_providerConfig"

    init(manager: AgentManager) {
        self.manager = manager
        if let data = UserDefaults.standard.data(forKey: "Hermes4Xcode_providerConfig"),
           let decoded = try? JSONDecoder().decode(ProviderConfig.self, from: data) {
            _config = State(initialValue: decoded)
            _selectedProvider = State(initialValue: decoded.provider)
        } else {
            _config = State(initialValue: ProviderConfig())
            _selectedProvider = State(initialValue: "deepseek")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Provider Settings")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.hermes)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color.hermes.opacity(0.3))

            ScrollView {
                VStack(spacing: 16) {
                    // ── Global Provider ──
                    globalProviderSection

                    Divider().background(Color.hermes.opacity(0.2))

                    // ── Agent Model Overrides ──
                    agentOverrideSection
                }
                .padding(16)
            }
        }
        .background(Color.black)
        .onAppear { loadAgentModels() }
    }

    // MARK: - Global Provider Section

    private var globalProviderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Provider (Gateway)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)

            Text("Used by agents that don't have a custom model override below.")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)

            // Provider selector
            VStack(alignment: .leading, spacing: 4) {
                Text("Provider")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                Picker("", selection: $selectedProvider) {
                    ForEach(AvailableProviders, id: \.name) { p in
                        Text(p.name).tag(p.name)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedProvider) { _, newVal in
                    if let match = AvailableProviders.first(where: { $0.name == newVal }) {
                        config.provider = newVal
                        config.model = match.defaultModel
                        config.baseURL = match.defaultURL
                    }
                }
            }

            // Model
            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                TextField("model name", text: $config.model)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8).background(Color(white: 0.15)).cornerRadius(6)
            }

            // Base URL
            VStack(alignment: .leading, spacing: 4) {
                Text("Base URL")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                TextField("https://...", text: $config.baseURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8).background(Color(white: 0.15)).cornerRadius(6)
            }

            // API Key
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                SecureField("sk-...", text: $config.apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8).background(Color(white: 0.15)).cornerRadius(6)
            }

            // Test & Save
            HStack(spacing: 12) {
                Button(action: testConnection) {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                        }
                        Text(isTesting ? "Testing..." : "Test Connection")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.hermes.opacity(0.15)).cornerRadius(4)
                }
                .buttonStyle(.plain).foregroundColor(.hermes)
                .disabled(isTesting || config.apiKey.isEmpty)

                Button(action: saveConfig) {
                    Text("Save")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Color.hermes).cornerRadius(4)
                }
                .buttonStyle(.plain).foregroundColor(.black)
            }

            // Test result
            if let result = testResult {
                HStack(spacing: 4) {
                    Image(systemName: result.hasPrefix("OK") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.hasPrefix("OK") ? .green : .red)
                        .font(.caption)
                    Text(result)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(result.hasPrefix("OK") ? .green : .red)
                }
                .padding(8)
                .background(Color(white: 0.12)).cornerRadius(6)
            }
        }
    }

    // MARK: - Agent Model Overrides

    private var agentOverrideSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Model Settings")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)

            Text("Override the model used by individual agents. Agents with vision needs (👁 UI Designer) should use a vision-capable model.")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)

            let agents = manager.tabs
            if agents.isEmpty {
                Text("No agents loaded. Open the Chat tab first.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(agents) { tab in
                        agentRow(tab: tab)
                        if tab.id != agents.last?.id {
                            Divider().background(Color.hermes.opacity(0.1))
                        }
                    }
                }
                .background(Color(white: 0.06)).cornerRadius(6)
            }
        }
    }

    private func agentRow(tab: AgentTab) -> some View {
        HStack(spacing: 8) {
            // Icon + name
            Image(systemName: tab.template.icon)
                .font(.system(size: 12))
                .foregroundColor(.hermes)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(tab.name)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                    if visionAgentNames.contains(tab.name) {
                        Text("👁")
                            .font(.system(size: 9))
                            .help("Vision-capable model recommended")
                    }
                }
                Text(tab.roleDescription.prefix(60) + (tab.roleDescription.count > 60 ? "..." : ""))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Model picker
            let binding = Binding<String>(
                get: { agentModels[tab.name] ?? "" },
                set: { agentModels[tab.name] = $0.isEmpty ? nil : $0 }
            )

            TextField("default", text: binding)
                .textFieldStyle(.plain)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(agentModels[tab.name] != nil ? .hermes : .secondary)
                .frame(width: 130)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(Color(white: 0.12)).cornerRadius(4)
                .help("Leave empty to use Gateway default model")

            // Reset button
            if agentModels[tab.name] != nil {
                Button(action: { agentModels.removeValue(forKey: tab.name) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to Gateway default")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    // MARK: - Actions

    func testConnection() {
        isTesting = true
        testResult = nil

        let urlStr = config.baseURL.hasSuffix("/v1") ? config.baseURL : config.baseURL + "/v1"
        guard let url = URL(string: "\(urlStr)/models") else {
            testResult = "Invalid URL"; isTesting = false; return
        }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                isTesting = false
                if let err = err {
                    testResult = "Connection failed: \(err.localizedDescription)"
                    return
                }
                if let httpResp = resp as? HTTPURLResponse {
                    if httpResp.statusCode == 200 {
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let models = json["data"] as? [[String: Any]] {
                            let names = models.prefix(3).compactMap { $0["id"] as? String }
                            testResult = "OK (\(httpResp.statusCode)) — \(models.count) models available"
                            if !names.isEmpty {
                                testResult! += "\n  e.g. \(names.joined(separator: ", "))"
                            }
                        } else {
                            testResult = "OK (\(httpResp.statusCode)) — server responded"
                        }
                    } else if httpResp.statusCode == 401 {
                        testResult = "Unauthorized (401) — check API key"
                    } else {
                        testResult = "HTTP \(httpResp.statusCode)"
                    }
                }
            }
        }.resume()
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        _ = XcodeContextProvider.shared.runShell(
            "hermes config set model.provider '\(config.provider)' 2>/dev/null"
        )
        _ = XcodeContextProvider.shared.runShell(
            "hermes config set model.default '\(config.model)' 2>/dev/null"
        )
        saveAgentModels()
        testResult = "Saved ✅"
    }

    private func loadAgentModels() {
        for tab in manager.tabs {
            if !tab.model.isEmpty {
                agentModels[tab.name] = tab.model
            }
            if !tab.provider.isEmpty {
                agentProviders[tab.name] = tab.provider
            }
        }
    }

    private func saveAgentModels() {
        for (name, model) in agentModels {
            if let idx = manager.tabs.firstIndex(where: { $0.name == name }) {
                manager.tabs[idx].model = model
            }
        }
        manager.autoSave()
    }
}
