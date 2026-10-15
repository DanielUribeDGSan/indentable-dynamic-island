import AppKit
import SwiftUI

struct IslandLayout: Equatable {
    var size: CGSize
    var selectionHeight: CGFloat
    var answerHeight: CGFloat
    var selectionScrolls: Bool
    var answerScrolls: Bool
    var compact: Bool

    static let tiny = IslandLayout(
        size: CGSize(width: 28, height: 12),
        selectionHeight: 0,
        answerHeight: 0,
        selectionScrolls: false,
        answerScrolls: false,
        compact: true
    )

    static let closed = IslandLayout(
        size: CGSize(width: 88, height: 22),
        selectionHeight: 0,
        answerHeight: 0,
        selectionScrolls: false,
        answerScrolls: false,
        compact: true
    )
}

enum IslandPhase: Equatable {
    case live
    case settings
}

final class IslandState: ObservableObject {
    @Published var isPresented = false
    @Published var shown = false
    @Published var phase: IslandPhase = .live
    @Published var layout: IslandLayout = .tiny
    @Published var selection = ""
    @Published var answer = ""
    @Published var error: String?
    @Published var isThinking = false
    @Published var accessibilityTrusted = false

    @Published var draftProvider: AIProvider = .gemini
    @Published var draftKey = ""
    @Published var revealKey = false
    @Published var draftModel = ""
    @Published var draftModels: [AIModel] = []
    @Published var isLoadingModels = false
    @Published var settingsStatus = ""

    var provider: AIProvider
    private var config: AppConfig
    private var selectionToken = 0
    private var requestGeneration = 0
    private var lastAsked = ""
    private var presentToken = 0
    private var openedDirectlyToSettings = false
    private var isClosing = false

    var onShow: ((NSPoint) -> Void)?
    var onHide: (() -> Void)?
    var onLayout: (() -> Void)?
    var onFocus: (() -> Void)?

    var showsBody: Bool {
        phase == .settings || !selection.isEmpty || !answer.isEmpty || isThinking || error != nil
    }

    var waveActive: Bool {
        isPresented && (layout.compact || isThinking)
    }

    init() {
        config = ConfigStore.load()
        provider = AIProvider(rawValue: config.provider) ?? .gemini
        draftProvider = provider
    }

    func toggleAtPointer() {
        if isPresented {
            dismiss()
        } else {
            presentAtPointer(phase: .live)
        }
    }

    func presentAtPointer(phase: IslandPhase) {
        if isPresented {
            if phase == .settings {
                enterSettings(direct: false)
            }
            return
        }
        present(at: NSEvent.mouseLocation, phase: phase, directSettings: phase == .settings)
    }

    func dismiss() {
        guard isPresented, !isClosing else { return }
        isClosing = true
        isThinking = false
        requestGeneration += 1
        selectionToken += 1
        presentToken += 1
        let token = presentToken
        withAnimation(IslandMetrics.close) {
            layout = .closed
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self, self.isClosing, token == self.presentToken else { return }
            self.isPresented = false
            self.isClosing = false
            self.shown = false
            self.onHide?()
        }
    }

    func closeSettings() {
        if openedDirectlyToSettings {
            dismiss()
        } else {
            settingsStatus = ""
            withAnimation(IslandMetrics.close) {
                phase = .live
                layout = computeLayout()
            }
            askCurrentSelection()
        }
    }

    func applySelection(_ raw: String) {
        guard isPresented, !isClosing, phase == .live else { return }
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 1, clean != selection else { return }
        selection = String(clean.prefix(12_000))
        answer = ""
        error = nil
        isThinking = false
        requestGeneration += 1
        refreshSize()
        scheduleAsk()
    }

    private func scheduleAsk() {
        selectionToken += 1
        let token = selectionToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, token == self.selectionToken, self.phase == .live, self.isPresented, !self.isClosing else { return }
            if NSEvent.pressedMouseButtons != 0 {
                self.scheduleAsk()
                return
            }
            self.askCurrentSelection()
        }
    }

    func askCurrentSelection() {
        let text = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text == lastAsked, !answer.isEmpty, error == nil {
            return
        }
        let key = config.key(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        let model = config.model(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            error = "Agrega tu API key en configuración."
            isThinking = false
            refreshSize()
            return
        }
        guard !model.isEmpty else {
            error = "Elige un modelo en configuración."
            isThinking = false
            refreshSize()
            return
        }

        requestGeneration += 1
        let generation = requestGeneration
        lastAsked = text
        answer = ""
        error = nil
        isThinking = true
        refreshSize()

        let activeProvider = provider
        DispatchQueue.global(qos: .userInitiated).async {
            RustCore.ask(provider: activeProvider, apiKey: key, model: model, text: text) { [weak self] chunk in
                guard let self, generation == self.requestGeneration else { return }
                self.answer += chunk
                self.refreshSize()
            } onDone: { [weak self] in
                guard let self, generation == self.requestGeneration else { return }
                self.isThinking = false
                if self.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.error = "El modelo no devolvió texto."
                }
                self.refreshSize()
            } onError: { [weak self] message in
                guard let self, generation == self.requestGeneration else { return }
                let safe = self.redact(message)
                if self.answer.isEmpty {
                    self.error = safe
                } else {
                    self.answer += "\n\n" + safe
                }
                self.isThinking = false
                self.refreshSize()
            }
        }
    }

    func setDraftProvider(_ provider: AIProvider) {
        draftProvider = provider
        draftKey = config.key(for: provider)
        draftModel = config.model(for: provider)
        draftModels = []
        revealKey = false
        settingsStatus = ""
    }

    func loadModels() {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            settingsStatus = "Escribe la API key primero."
            return
        }
        isLoadingModels = true
        settingsStatus = "Buscando modelos…"
        let provider = draftProvider
        DispatchQueue.global(qos: .userInitiated).async {
            let result = RustCore.listModels(provider: provider, apiKey: key)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.draftProvider == provider else { return }
                self.isLoadingModels = false
                switch result {
                case .success(var models):
                    if !self.draftModel.isEmpty, !models.contains(where: { $0.id == self.draftModel }) {
                        models.insert(AIModel(id: self.draftModel, label: "\(self.draftModel) (guardado)"), at: 0)
                    }
                    self.draftModels = models
                    if self.draftModel.isEmpty, let first = models.first {
                        self.draftModel = first.id
                    }
                    self.settingsStatus = "\(models.count) modelos actuales."
                case .failure(let error):
                    self.draftModels = []
                    self.settingsStatus = self.redact(error.description)
                }
            }
        }
    }

    func saveSettings() {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            settingsStatus = "La API key está vacía."
            return
        }
        config.provider = draftProvider.rawValue
        config.setKey(key, for: draftProvider)
        config.setModel(draftModel.trimmingCharacters(in: .whitespacesAndNewlines), for: draftProvider)
        ConfigStore.save(config)
        provider = draftProvider
        settingsStatus = "Guardado. El texto que selecciones se responderá con \(draftProvider.title)."
        lastAsked = ""
    }

    func islandRect(in bounds: CGRect) -> CGRect {
        let size = layout.size
        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func present(at point: NSPoint, phase: IslandPhase, directSettings: Bool) {
        self.phase = phase
        openedDirectlyToSettings = directSettings
        if phase == .settings {
            loadDraft()
        }
        presentToken += 1
        isClosing = false
        layout = .closed
        shown = true
        isPresented = true
        onShow?(point)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        if phase == .settings {
            DispatchQueue.main.async { [weak self] in self?.onFocus?() }
        }
        let token = presentToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self, self.isPresented, !self.isClosing, token == self.presentToken else { return }
            withAnimation(IslandMetrics.open) {
                self.layout = self.computeLayout()
            }
        }
    }

    private func enterSettings(direct: Bool) {
        openedDirectlyToSettings = direct
        loadDraft()
        isClosing = false
        withAnimation(IslandMetrics.open) {
            phase = .settings
            layout = computeLayout()
        }
        onFocus?()
    }

    private func loadDraft() {
        draftProvider = provider
        draftKey = config.key(for: provider)
        draftModel = config.model(for: provider)
        draftModels = []
        revealKey = false
        settingsStatus = ""
        if !draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loadModels()
        }
    }

    private func refreshSize() {
        guard isPresented, !isClosing else { return }
        let next = computeLayout()
        guard next != layout else { return }
        withAnimation(IslandMetrics.open) {
            layout = next
        }
        onLayout?()
    }

    private func computeLayout() -> IslandLayout {
        guard isPresented else { return .tiny }
        if phase == .settings {
            return IslandLayout(
                size: CGSize(width: 430, height: 600),
                selectionHeight: 0,
                answerHeight: 0,
                selectionScrolls: false,
                answerScrolls: false,
                compact: false
            )
        }
        guard showsBody else {
            return IslandLayout(
                size: CGSize(width: 300, height: 72),
                selectionHeight: 0,
                answerHeight: 0,
                selectionScrolls: false,
                answerScrolls: false,
                compact: true
            )
        }

        let inner = CGFloat(selection.count > 80 || selection.contains("\n") ? 430 : 360)
        let width = min(540, max(340, inner + 36))
        let textWidth = width - 32
        let titleFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let rawTitle = measuredHeight(selection, font: titleFont, width: textWidth) + 8
        let titleHeight = min(150, max(22, rawTitle))
        let answerSource = error ?? answer
        let rawAnswer = markdownAnswerHeight(answerSource, width: textWidth)
        let thinkingExtra: CGFloat = isThinking && answer.isEmpty && error == nil ? 28 : 0
        let answerCap: CGFloat = 250
        let unsnappedAnswer = answerSource.isEmpty && thinkingExtra == 0 ? 0 : min(answerCap, max(thinkingExtra, rawAnswer))
        let answerHeight = snap(unsnappedAnswer, step: 20)
        let column = 22 + titleHeight
        let row = max(72, column)
        var height = 8 + row + 14
        if answerHeight > 0 {
            height += 8 + answerHeight
        }
        height += 18
        return IslandLayout(
            size: CGSize(width: width, height: min(600, snap(height, step: 8))),
            selectionHeight: titleHeight,
            answerHeight: answerHeight,
            selectionScrolls: rawTitle > 150,
            answerScrolls: rawAnswer > answerCap,
            compact: false
        )
    }

    private func snap(_ value: CGFloat, step: CGFloat) -> CGFloat {
        guard value > 0 else { return 0 }
        return ceil(value / step) * step
    }

    private func measuredHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: 4_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(rect.height)
    }

    private func redact(_ message: String) -> String {
        var output = message
        for key in [config.geminiKey, config.openAIKey, draftKey] where key.count > 6 {
            output = output.replacingOccurrences(of: key, with: "•••")
        }
        return output
    }
}
