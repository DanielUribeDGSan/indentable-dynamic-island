import Foundation

struct AppConfig: Codable {
    var provider: String = AIProvider.gemini.rawValue
    var geminiKey: String = ""
    var openAIKey: String = ""
    var geminiModel: String = ""
    var openAIModel: String = ""

    func key(for provider: AIProvider) -> String {
        switch provider {
        case .gemini: return geminiKey
        case .openAI: return openAIKey
        }
    }

    func model(for provider: AIProvider) -> String {
        switch provider {
        case .gemini: return geminiModel
        case .openAI: return openAIModel
        }
    }

    mutating func setKey(_ key: String, for provider: AIProvider) {
        switch provider {
        case .gemini: geminiKey = key
        case .openAI: openAIKey = key
        }
    }

    mutating func setModel(_ model: String, for provider: AIProvider) {
        switch provider {
        case .gemini: geminiModel = model
        case .openAI: openAIModel = model
        }
    }
}

enum ConfigStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DynamicIsland/config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL) else { return AppConfig() }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    static func save(_ config: AppConfig) {
        let url = fileURL
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
