import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Whether the composer's model pill should show the "Auto" badge — i.e. the
/// router is resolving the model each turn rather than a user pin winning
/// outright (mirrors `ModelRouter.route`'s own "pin wins over everything"
/// rule). Pure — unit tested without SwiftUI/AppEnvironment.
func modelPillShowsAutoBadge(pinnedModel: String?, routerEnabled: Bool) -> Bool {
    pinnedModel == nil && routerEnabled
}

/// Whether the composer model pill's SELECTION should sit on the "Auto" row
/// rather than a specific connection·model pair. Currently the exact same
/// rule as `modelPillShowsAutoBadge` — a separate name documents that this
/// drives the picker's selection sentinel, not just the badge glyph, so the
/// two can diverge later without silently breaking either call site.
func modelPillSelectionIsAuto(pinnedModel: String?, routerEnabled: Bool) -> Bool {
    modelPillShowsAutoBadge(pinnedModel: pinnedModel, routerEnabled: routerEnabled)
}

/// The model the pill DISPLAYS: an explicit pin always wins (matches
/// `ModelRouter.route`'s pin precedence); absent a pin, an enabled router
/// shows the model it last actually resolved to, falling back to the
/// standing default before any turn has settled; a disabled router with no
/// pin shows the standing default. Pure.
func modelPillDisplayModel(
    pinnedModel: String?, routerEnabled: Bool,
    lastResolvedModel: String?, standingDefault: String
) -> String {
    if let pinnedModel { return pinnedModel }
    if routerEnabled { return lastResolvedModel ?? standingDefault }
    return standingDefault
}

/// True when `model` is one of `curatedModels` (`ProviderPreset.curatedModels`
/// for the owning connection) — drives the verified/curated glyph in the
/// model picker's option rows. Pure.
func isCuratedModel(_ model: String, curatedModels: [String]) -> Bool {
    curatedModels.contains(model)
}

/// Option-row label for a (connection, model) pair: "Connection · Model",
/// prefixed with a verified/curated glyph when the model is one of the
/// connection's curated presets. Pure — the exact string
/// `SageConnectionModelPicker`'s row label renders.
func modelOptionRowLabel(connectionName: String, model: String, isCurated: Bool) -> String {
    let prefix = isCurated ? "✓ " : ""
    return "\(prefix)\(connectionName) · \(model)"
}

/// The provider swatch color for a connection's `ProviderKind` — a fixed,
/// theme-independent brand accent (not `theme.*`, since it identifies the
/// PROVIDER, not the app theme) shown as the grouped picker row's leading
/// dot. Pure.
func providerSwatchColor(for kind: ProviderKind) -> Color {
    switch kind {
    case .claude: return Color(hex: "CC785C")
    case .gemini: return Color(hex: "4285F4")
    case .openAICompatible: return Color(hex: "10A37F")
    }
}

/// Builds the grouped model picker's section list: an "Auto" section first
/// (its detail names the active connection when one exists, so the row isn't
/// bare), then one section per connection (header = its `displayName`) whose
/// rows enrich each model with a local/cloud SF Symbol, a provider swatch, a
/// curated (✓) marker, and reachability. Per the offline rule, a row is
/// disabled with a "server down" detail ONLY when its connection is LOCAL
/// (`isLocal`) and not in `reachable`; cloud connections are always enabled
/// regardless of `reachable`'s contents. A trailing "Manage connections…"
/// section keeps that affordance reachable and always enabled. Pure — unit
/// tested without SwiftUI/AppEnvironment.
func modelPickerSections(
    connections: [Connection],
    modelsFor: (Connection) -> [String],
    curatedFor: (Connection) -> [String],
    isLocal: (Connection) -> Bool,
    reachable: Set<UUID>,
    activeConnectionID: UUID?
) -> [AinkradGroupedSection<SageConnectionModelPicker.Option>] {
    let autoDetail = connections.first(where: { $0.id == activeConnectionID }).map { "via \($0.displayName)" }
    var sections: [AinkradGroupedSection<SageConnectionModelPicker.Option>] = [
        AinkradGroupedSection(
            header: "Auto",
            rows: [
                AinkradGroupedRow(value: .auto, title: "Auto", detail: autoDetail, icon: "wand.and.stars")
            ])
    ]

    for connection in connections {
        let local = isLocal(connection)
        let enabled = local ? reachable.contains(connection.id) : true
        let curatedModels = curatedFor(connection)
        let rows = modelsFor(connection).map { model -> AinkradGroupedRow<SageConnectionModelPicker.Option> in
            let curated = isCuratedModel(model, curatedModels: curatedModels)
            let detail: String
            if !enabled {
                detail = "server down"
            } else {
                var parts: [String] = []
                if curated { parts.append("✓ curated") }
                parts.append(local ? "local" : "cloud")
                detail = parts.joined(separator: " · ")
            }
            return AinkradGroupedRow(
                value: .pair(connection: connection.id, model: model),
                title: model,
                detail: detail,
                icon: local ? "desktopcomputer" : "icloud",
                swatch: providerSwatchColor(for: connection.kind),
                isEnabled: enabled
            )
        }
        sections.append(AinkradGroupedSection(header: connection.displayName, rows: rows))
    }

    sections.append(
        AinkradGroupedSection(
            header: "",
            rows: [
                AinkradGroupedRow(value: .manage, title: SageConnectionModelPicker.manageLabel, icon: "gearshape")
            ]))

    return sections
}

/// Whether `refreshModels` should hit the network for a connection: skip when a
/// fetch is already in flight, or when the last fetch attempt (success OR
/// failure) is younger than `ttl`. Pure — unit tested without I/O.
func shouldFetchModels(
    connectionID: UUID, now: Date, lastFetch: [UUID: Date],
    inFlight: Set<UUID>, ttl: TimeInterval
) -> Bool {
    if inFlight.contains(connectionID) { return false }
    if let last = lastFetch[connectionID], now.timeIntervalSince(last) < ttl { return false }
    return true
}

/// The ONE home for the Sage's connection+model selection logic, previously
/// duplicated in `SageRootView` and `SageSettingsView`. Consumers hold
/// it as `@State`; methods take the `AppEnvironment` so it stays decoupled.
@MainActor
@Observable
final class SageModelPickerModel {
    var isRefreshing = false

    /// Discovery cache: last fetch-attempt time per connection (recorded on any
    /// completion, success or failure), and
    /// connections with a fetch currently in flight. Backs `shouldFetchModels`
    /// so `refreshModels` doesn't re-hit `/models` on every picker `.onAppear`
    /// / connection switch.
    private var lastFetch: [UUID: Date] = [:]
    private var inFlight: Set<UUID> = []
    private static let discoveryTTL: TimeInterval = 300  // 5 min

    /// The active connection: the configured one if it still exists, else the
    /// first connection.
    func activeConnection(_ environment: AppEnvironment) -> Connection? {
        let store = environment.connectionStore
        if let id = environment.agentConfigStore.activeConnectionID,
            let match = store.connections.first(where: { $0.id == id })
        {
            return match
        }
        return store.connections.first
    }

    /// Models to offer for a connection: the shared store's live-discovered list
    /// if one was fetched, else the preset's curated fallback.
    func modelOptions(for connection: Connection?, _ environment: AppEnvironment) -> [String] {
        guard let connection else { return [] }
        return environment.discoveredModelsStore.models(for: connection.id)
            ?? ProviderPreset.preset(id: connection.presetID).curatedModels
    }

    /// Kick a live refresh for EVERY configured connection (not just the active
    /// one), so the dropdown shows live models for all providers and the router's
    /// candidate store is populated for each. Each fetch is independent and
    /// non-blocking; a failed one silently leaves the curated fallback in place.
    func refreshAllModels(_ environment: AppEnvironment) {
        for connection in environment.connectionStore.connections {
            refreshModels(for: connection, environment)
        }
    }

    /// Switch the active connection AND reset its model to the curated default,
    /// then kick a live refresh.
    func selectConnection(_ connection: Connection, _ environment: AppEnvironment) {
        let configStore = environment.agentConfigStore
        configStore.setActiveConnectionID(connection.id)
        configStore.setModel(
            ProviderPreset.preset(id: connection.presetID).curatedModels.first ?? configStore.current.model)
        refreshModels(for: connection, environment)
    }

    /// Switch to a specific connection + model together (used by the grouped
    /// pill, which lists a model under its owning connection). Also pins the
    /// model for the session (`RuntimeOptionsStore.pinModel`) — an explicit
    /// pick from the pill is an explicit pin, same as `/model <id>`.
    func selectConnectionModel(_ connection: Connection, model: String, _ environment: AppEnvironment) {
        let configStore = environment.agentConfigStore
        configStore.setActiveConnectionID(connection.id)
        configStore.setModel(model)
        environment.runtimeOptionsStore.pinModel(model)
    }

    /// Return the pill to "Auto": clears any explicit pin so the router picks
    /// the model each turn again — the pill-side counterpart to `/model auto`.
    func clearPin(_ environment: AppEnvironment) {
        environment.runtimeOptionsStore.pinModel(nil)
    }

    func refreshModels(for connection: Connection, _ environment: AppEnvironment, force: Bool = false) {
        if !force
            && !shouldFetchModels(
                connectionID: connection.id, now: Date(),
                lastFetch: lastFetch, inFlight: inFlight, ttl: Self.discoveryTTL)
        {
            return
        }
        let store = environment.connectionStore
        let svc = environment.modelCatalogService
        let preset = ProviderPreset.preset(id: connection.presetID)
        let oauthStore = environment.oauthStore
        isRefreshing = true
        inFlight.insert(connection.id)
        Task {
            defer {
                lastFetch[connection.id] = Date()
                inFlight.remove(connection.id)
            }
            // A subscription connection is keyless — resolve its OAuth bearer (with
            // refresh) so discovery hits `/models` authenticated. If no token is
            // stored yet (not signed in), fall through with an empty key, which
            // leaves the curated fallback in place. API-key connections use their key.
            let credential: ProviderCredential
            if connection.authMode == .subscription {
                credential = (try? await oauthStore.liveCredential(for: connection)) ?? .apiKey("")
            } else {
                credential = .apiKey(store.token(for: connection) ?? "")
            }
            let result = await svc.modelsResult(
                kind: connection.kind, baseURL: connection.baseURL,
                credential: credential, curatedFallback: preset.curatedModels)
            isRefreshing = false
            // Persist ONLY a genuinely live list into the shared store — a curated
            // fallback is already the default, so storing it would be redundant and
            // could mask a later real discovery. `setModels` also ignores empties.
            if result.isLive {
                environment.discoveredModelsStore.setModels(result.models, for: connection.id)
                reconcileModelIfNeeded(for: connection, availableModels: result.models, environment)
            }
        }
        // Piggyback a reachability refresh on the same user-triggered moment
        // (connection switch / picker open / manual refresh button) so the
        // Auto router's local-candidate gate (`AppEnvironment.candidatesProvider`)
        // reflects "is the local server up right now" without waiting for the
        // background 30s loop.
        Task {
            await environment.localModelAvailability.refresh(
                connections: store.connections, probe: environment.localModelProbe,
                tokenFor: { store.token(for: $0) })
        }
    }

    /// If the active connection's model isn't valid for it (e.g. the Claude
    /// default on a fresh non-Claude connection), fall back to the first
    /// available model. Never overrides an explicitly chosen valid model. Only
    /// called on a genuinely live fetch — never on a curated fallback.
    private func reconcileModelIfNeeded(
        for connection: Connection, availableModels: [String], _ environment: AppEnvironment
    ) {
        let configStore = environment.agentConfigStore
        guard activeConnection(environment)?.id == connection.id else { return }
        guard !availableModels.isEmpty, !availableModels.contains(configStore.current.model) else { return }
        configStore.setModel(availableModels[0])
    }
}

/// The composer's connection·model picker: ONE searchable select (never a
/// nested `Menu`) whose options are `(connection, model)` pairs rendered
/// "Connection · Model", plus a trailing "Manage connections…" sentinel.
/// Selecting a pair switches connection + model together; the sentinel opens
/// Sage settings WITHOUT mutating the selection. Seamless — the kit
/// control carries its own chamfer chrome.
struct SageConnectionModelPicker: View {
    @Environment(AppEnvironment.self) private var environment
    let model: SageModelPickerModel
    @Environment(\.ainkradTheme) private var theme
    var onManageConnections: () -> Void

    /// The flattened option space: a real connection+model pair, the "Manage
    /// connections…" sentinel, or an empty placeholder when no connection exists.
    /// Not `private` — the free `modelPickerSections` builder above returns
    /// `AinkradGroupedSection<Option>` and needs to name the type.
    enum Option: Hashable {
        case auto
        case pair(connection: UUID, model: String)
        case manage
        case empty
    }

    /// Not `private` — referenced by `modelPickerSections` for the trailing
    /// "Manage connections…" row's title.
    static let manageLabel = "Manage connections…"

    var body: some View {
        let connections = environment.connectionStore.connections
        let active = model.activeConnection(environment)
        let binding = selectionBinding(active: active)

        let sections = modelPickerSections(
            connections: connections,
            modelsFor: { model.modelOptions(for: $0, environment) },
            curatedFor: { ProviderPreset.preset(id: $0.presetID).curatedModels },
            isLocal: { environment.localModelProbe.isLocal($0) },
            reachable: environment.localModelAvailability.reachableConnectionIDs,
            activeConnectionID: active?.id
        )

        return HStack(spacing: AinkradSpacing.xs) {
            AinkradGroupedSelect(
                sections: sections,
                selection: binding,
                triggerLabel: label(binding.wrappedValue),
                searchPlaceholder: "Search connections & models…"
            )
            .fixedSize()
            // Bordered trigger's own padding (AinkradSpacing.sm vertical) runs
            // taller than the composer's icon buttons; pin the row height so
            // the control cluster reads as one consistent height — see
            // `SageComposerBar.controlHeight` (Wave 3e: whole strip
            // unified to 30).
            .frame(height: SageComposerBar.controlHeight)
            .onAppear { model.refreshAllModels(environment) }
            .onChange(of: active?.id) { _, _ in if let c = active { model.refreshModels(for: c, environment) } }

            routingBadge
        }
    }

    /// "AUTO" when the router is resolving the model each turn, "PINNED" when
    /// the user has pinned one — NOT a native control, just a themed
    /// `AinkradBadge`.
    /// No badge at all when the router is disabled and nothing is pinned
    /// (today's plain default-model behavior, unchanged).
    @ViewBuilder
    private var routingBadge: some View {
        let pinned = environment.runtimeOptionsStore.options.pinnedModel
        if pinned != nil {
            AinkradBadge(text: "Pinned", tint: theme.accentPrimary)
        }
    }

    /// Maps the store's live selection to the matching pair (or `.empty`) for the
    /// getter, and routes the setter: a real pair → `selectConnectionModel`; the
    /// sentinel → `onManageConnections()` with NO model mutation (the computed
    /// getter re-reads the unchanged store, so the trigger label reverts on its
    /// own). The getter never crashes when the current model isn't yet in the
    /// discovered list — it still resolves a "Connection · Model" label.
    ///
    /// The displayed model is resolved via `modelPillDisplayModel`: a pin always
    /// wins; absent a pin, an enabled router shows the model it last actually
    /// resolved to (`AgentSession.lastUsageAttributedModel`) rather than the
    /// standing config default, so "Auto" reflects what really ran.
    private func selectionBinding(active: Connection?) -> Binding<Option> {
        Binding(
            get: {
                guard let active else { return .empty }
                let pinned = environment.runtimeOptionsStore.options.pinnedModel
                let routerEnabled = environment.agentStore.active.routing.routerEnabled
                if modelPillSelectionIsAuto(pinnedModel: pinned, routerEnabled: routerEnabled) {
                    return .auto
                }
                let displayModel = modelPillDisplayModel(
                    pinnedModel: pinned,
                    routerEnabled: routerEnabled,
                    lastResolvedModel: environment.agentSession.lastUsageAttributedModel,
                    standingDefault: environment.agentConfigStore.current.model)
                return .pair(connection: active.id, model: displayModel)
            },
            set: { option in
                switch option {
                case .auto:
                    model.clearPin(environment)
                case .pair(let connectionID, let modelName):
                    if let connection = environment.connectionStore.connections.first(where: { $0.id == connectionID })
                    {
                        model.selectConnectionModel(connection, model: modelName, environment)
                    }
                case .manage:
                    onManageConnections()
                case .empty:
                    break
                }
            }
        )
    }

    private func label(_ option: Option) -> String {
        switch option {
        case .auto:
            return "Auto"
        case .empty:
            return "No connection"
        case .manage:
            return SageConnectionModelPicker.manageLabel
        case .pair(let connectionID, let modelName):
            guard let connection = environment.connectionStore.connections.first(where: { $0.id == connectionID })
            else {
                return "Connection · \(modelName)"
            }
            let curated = isCuratedModel(
                modelName, curatedModels: ProviderPreset.preset(id: connection.presetID).curatedModels)
            return modelOptionRowLabel(connectionName: connection.displayName, model: modelName, isCurated: curated)
        }
    }
}
