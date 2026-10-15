import Foundation
import CRustCore

struct AIModel: Identifiable, Hashable, Decodable {
    let id: String
    let label: String
}

struct EngineError: Error, CustomStringConvertible {
    let description: String
}

enum AIProvider: String, CaseIterable, Identifiable {
    case gemini
    case openAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gemini: return "Gemini"
        case .openAI: return "OpenAI"
        }
    }

    var engineID: String {
        switch self {
        case .gemini: return "gemini"
        case .openAI: return "openai"
        }
    }
}

private struct ModelsEnvelope: Decodable {
    let ok: Bool
    let models: [AIModel]?
    let error: String?
}

private final class AskSession {
    let onChunk: (String) -> Void
    let onDone: () -> Void
    let onError: (String) -> Void

    init(onChunk: @escaping (String) -> Void, onDone: @escaping () -> Void, onError: @escaping (String) -> Void) {
        self.onChunk = onChunk
        self.onDone = onDone
        self.onError = onError
    }
}

private let islandStreamTrampoline: IslandStreamFn = { chunk, isError, isDone, ctx in
    guard let ctx else { return }
    let session = Unmanaged<AskSession>.fromOpaque(ctx).takeUnretainedValue()
    let text = chunk.map { String(cString: $0) } ?? ""
    let failed = isError != 0
    let done = isDone != 0
    DispatchQueue.main.async {
        if failed {
            session.onError(text)
        } else if done {
            session.onDone()
        } else if !text.isEmpty {
            session.onChunk(text)
        }
    }
}

enum RustCore {
    static var version: String {
        guard let pointer = island_engine_version() else { return "rust" }
        return String(cString: pointer)
    }

    static func listModels(provider: AIProvider, apiKey: String) -> Result<[AIModel], EngineError> {
        let raw: UnsafeMutablePointer<CChar>? = provider.engineID.withCString { providerPointer in
            apiKey.withCString { keyPointer in
                island_list_models(providerPointer, keyPointer)
            }
        }
        guard let raw else { return .failure(EngineError(description: "El motor no respondió.")) }
        defer { island_free_string(raw) }
        let json = String(cString: raw)
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ModelsEnvelope.self, from: data) else {
            return .failure(EngineError(description: "No se pudo leer el listado de modelos."))
        }
        if envelope.ok, let models = envelope.models, !models.isEmpty {
            return .success(models)
        }
        return .failure(EngineError(description: envelope.error ?? "No hay modelos disponibles."))
    }

    static func ask(
        provider: AIProvider,
        apiKey: String,
        model: String,
        text: String,
        onChunk: @escaping (String) -> Void,
        onDone: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        let session = AskSession(onChunk: onChunk, onDone: onDone, onError: onError)
        let context = Unmanaged.passRetained(session).toOpaque()
        provider.engineID.withCString { providerPointer in
            apiKey.withCString { keyPointer in
                model.withCString { modelPointer in
                    text.withCString { textPointer in
                        island_ask(providerPointer, keyPointer, modelPointer, textPointer, islandStreamTrampoline, context)
                    }
                }
            }
        }
        Unmanaged<AskSession>.fromOpaque(context).release()
    }
}
