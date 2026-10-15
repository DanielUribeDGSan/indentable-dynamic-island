import SwiftUI

struct IslandView: View {
    @ObservedObject var state: IslandState
    @FocusState private var keyFocused: Bool
    @State private var modelQuery = ""

    private var visibleModels: [AIModel] {
        let query = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return state.draftModels }
        return state.draftModels.filter {
            $0.id.lowercased().contains(query) || $0.label.lowercased().contains(query)
        }
    }

    private var shape: IslandShape {
        IslandShape(radius: state.layout.compact ? 24 : 36)
    }

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
    }

    private var island: some View {
        ZStack {
            shape
                .fill(Color.black)
                .shadow(color: Color.black.opacity(0.22), radius: 8, y: 3)

            layeredContent
                .padding(.horizontal, 16)
                .padding(.vertical, state.layout.compact && state.phase != .settings ? 0 : 12)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: state.layout.compact && state.phase != .settings ? .center : .top
                )
                .clipShape(shape)
        }
        .frame(width: state.layout.size.width, height: state.layout.size.height, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var layeredContent: some View {
        if state.phase == .settings {
            settings
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeInOut(duration: 0.25).delay(0.18)),
                    removal: .opacity.animation(.easeInOut(duration: 0.15))
                ))
        } else if state.layout.compact {
            compactRow
                .transition(.opacity.animation(.linear(duration: 0.05)))
        } else {
            expanded
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeInOut(duration: 0.25).delay(0.18)),
                    removal: .opacity.animation(.easeInOut(duration: 0.15))
                ))
        }
    }

    private var compactRow: some View {
        HStack(spacing: 10) {
            orb(side: 48)
            Group {
                if state.accessibilityTrusted {
                    Text("Selecciona texto")
                        .foregroundStyle(IslandPalette.paper)
                } else {
                    Button("Activa Accesibilidad") {
                        SelectionMonitor.openSettings()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(IslandPalette.paper)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            Spacer(minLength: 0)
            iconButton("gearshape.fill", action: openSettings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                orb(side: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("EN VIVO")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(IslandPalette.cloud)
                    selectionBlock
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 6) {
                    iconButton("gearshape.fill", action: openSettings)
                    iconButton("xmark", action: state.dismiss)
                }
            }

            if state.layout.answerHeight > 0 {
                answerBlock
                    .frame(height: state.layout.answerHeight)
            }
        }
    }

    @ViewBuilder
    private var selectionBlock: some View {
        let text = Text(state.selection.isEmpty ? "Selecciona texto en el navegador" : state.selection)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(IslandPalette.paper)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        if state.layout.selectionScrolls {
            ScrollView { text.padding(.vertical, 1) }
                .frame(height: state.layout.selectionHeight)
        } else {
            text.frame(height: state.layout.selectionHeight, alignment: .topLeading)
        }
    }

    private var answerBlock: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if state.isThinking && state.answer.isEmpty && state.error == nil {
                    Text("Pensando…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(IslandPalette.mist)
                }
                if let error = state.error, state.answer.isEmpty {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(IslandPalette.cloud)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !state.answer.isEmpty {
                    MarkdownAnswer(source: state.answer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 2)
        }
        .scrollIndicators(state.layout.answerScrolls ? .visible : .hidden)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                orb(side: 36)
                Text("Configuración")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IslandPalette.paper)
                Spacer()
                iconButton("xmark", action: state.closeSettings)
            }

            HStack(spacing: 8) {
                ForEach(AIProvider.allCases) { provider in
                    Button(provider.title) {
                        state.setDraftProvider(provider)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(state.draftProvider == provider ? IslandPalette.ink : IslandPalette.cloud)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        state.draftProvider == provider ? IslandPalette.paper : IslandPalette.graphite,
                        in: Capsule()
                    )
                }
            }

            Text("API key de \(state.draftProvider.title)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(IslandPalette.mist)

            HStack(spacing: 8) {
                Group {
                    if state.revealKey {
                        TextField("Pega tu API key", text: $state.draftKey)
                    } else {
                        SecureField("Pega tu API key", text: $state.draftKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(IslandPalette.paper)
                .focused($keyFocused)

                Button(state.revealKey ? "Ocultar" : "Ver") {
                    state.revealKey.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandPalette.silver)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(IslandPalette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: keyFocused) { _, focused in
                if focused { state.onFocus?() }
            }

            Button(action: state.loadModels) {
                HStack(spacing: 6) {
                    if state.isLoadingModels {
                        ProgressView().controlSize(.small).tint(IslandPalette.paper)
                    }
                    Text(state.isLoadingModels ? "Cargando modelos…" : "Ver modelos actuales")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandPalette.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(IslandPalette.graphite, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(state.isLoadingModels)

            Text("Modelo")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(IslandPalette.mist)

            TextField("Buscar: luna, gemini, gpt…", text: $modelQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(IslandPalette.paper)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(IslandPalette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: state.draftProvider) { _, _ in
                    modelQuery = ""
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if state.draftModels.isEmpty {
                        Text(state.isLoadingModels
                             ? "Buscando todos los modelos…"
                             : (state.settingsStatus.isEmpty
                                ? "Pulsa “Ver modelos actuales” para traer todos los modelos de tu clave."
                                : state.settingsStatus))
                            .font(.system(size: 12))
                            .foregroundStyle(IslandPalette.cloud)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                    } else if visibleModels.isEmpty {
                        let typed = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nada coincide. Luna 6 es gpt-6-luna. Escribe el id completo.")
                                .font(.system(size: 12))
                                .foregroundStyle(IslandPalette.stone)
                            if typed.contains("-") || typed.lowercased().contains("gpt") || typed.lowercased().contains("gemini") {
                                Button("Usar \(typed)") {
                                    state.draftModel = typed
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(IslandPalette.paper)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                    } else {
                        ForEach(visibleModels) { model in
                            Button {
                                state.draftModel = model.id
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(model.label)
                                            .lineLimit(1)
                                        if model.label != model.id {
                                            Text(model.id)
                                                .font(.system(size: 10))
                                                .foregroundStyle(IslandPalette.stone)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if state.draftModel == model.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(IslandPalette.paper)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    state.draftModel == model.id ? IslandPalette.graphite : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(height: 200)
            .layoutPriority(1)

            Button(action: state.saveSettings) {
                Text("Guardar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(IslandPalette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(IslandPalette.paper, in: Capsule())
            }
            .buttonStyle(.plain)

            Text(state.settingsStatus)
                .font(.system(size: 11))
                .foregroundStyle(IslandPalette.mist)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(IslandPalette.cloud)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func orb(side: CGFloat) -> some View {
        LiquidOrbView(state: state.isThinking ? .thinking : .idle, active: state.isPresented)
            .frame(width: side, height: side)
            .allowsHitTesting(false)
    }

    private func openSettings() {
        state.presentAtPointer(phase: .settings)
    }
}
