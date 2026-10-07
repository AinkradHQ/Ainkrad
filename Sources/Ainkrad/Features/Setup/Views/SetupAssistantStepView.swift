import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Applies the Sage step. `AgentStore.setActive` is a no-op unless the id is
/// already in `agents`, so a custom profile must be added before it is activated.
@MainActor
enum SetupAssistant {
    static func apply(
        profile: AgentProfile, model: String, effort: String,
        agents: AgentStore, config: AgentConfigStore
    ) {
        let resolved: AgentProfile
        if profile.builtin {
            resolved = profile
        } else if agents.agents.contains(where: { $0.id == profile.id }) {
            // Back-then-Continue on the same custom persona: update the
            // existing entry in place rather than appending a duplicate.
            // `commit()` reuses the same `AgentProfile.id` across the step's
            // session, so this branch is what makes that reuse matter.
            agents.update(profile)
            resolved = profile
        } else {
            resolved = agents.add(profile)
        }
        agents.setActive(resolved.id)
        config.setModel(model)
        config.setEffort(effort)
    }

    /// The model to seed the step with: the active connection's first curated
    /// model, mirroring `SageModelPickerModel.selectConnection`
    /// (Sources/Ainkrad/Features/Sage/SageModelPicker.swift
    /// ~lines 178-180) — the existing precedent for defaulting a model off a
    /// connection rather than a hardcoded Anthropic id. Falls back to
    /// `AgentConfigDocument`'s own default only when there is no connection
    /// to key off (a fresh install with nothing configured yet). Static
    /// `curatedModels` data — no live network call.
    static func defaultModel(connections: [Connection], activeConnectionID: UUID?) -> String {
        let connection =
            activeConnectionID.flatMap { id in connections.first { $0.id == id } }
            ?? connections.first
        guard let connection else { return AgentConfigDocument().model }
        return ProviderPreset.preset(id: connection.presetID).curatedModels.first
            ?? AgentConfigDocument().model
    }
}

/// The Sage step: a confirmation, not an authoring task. Plan and Build —
/// the two built-in agents — are shown with their instructions so the user can
/// see what they do; Build is the default (matching `AgentStore.active`'s own
/// fallback). A custom persona is a secondary path via `AgentProfile.custom`,
/// added to the store only on Continue (never on every keystroke, unlike the
/// You step — an agent profile isn't a fact to accumulate, it's a choice to commit).
///
/// Model defaults to the active connection's curated model (see
/// `SetupAssistant.defaultModel`) rather than a live model-list call: in this
/// developer's judgment (informed by this task's dispatch context, not a
/// stated brief requirement) a network fetch here could hang the wizard on a
/// flaky connection, and curated data is static and instant. Effort defaults
/// to `AgentConfigDocument`'s own default (`"xhigh"`).
///
/// Model and effort persist immediately on change (plain scalars, no
/// partial-typing risk — same convention as the Appearance/You steps); only
/// the custom-persona commit stays gated on Continue, since a half-typed
/// name/instructions shouldn't become the active agent mid-edit.
struct SetupAssistantStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.setupGroupWidth) private var groupWidth
    @Environment(\.ainkradSkin) private var skin

    let coordinator: SetupCoordinator

    private static let efforts = ["low", "medium", "high", "xhigh"]

    /// The rules live in `SetupValidation`, not in a `.disabled(...)` here, so
    /// the next change to what this step requires is one file. `isCustom` is
    /// view state, so the view is what turns it into the dictionary's
    /// `"isCustom"` entry — the validator stays pure.
    private var unmet: [SetupValidation.Requirement] {
        SetupValidation.unmet(
            for: .assistant,
            values: [
                "isCustom": isCustom ? "true" : "false",
                "personaName": customName,
                "personaInstructions": customInstructions,
            ])
    }

    /// Same rule as the You step's: the warning appears once the user has typed
    /// in the field and left it blank, not the instant the custom-persona
    /// fields appear. Two warnings under two fields the user has only just
    /// revealed reads as an error state rather than guidance, and both steps
    /// should answer "when does a warning appear" the same way. Continue stays
    /// disabled throughout either way.
    private func message(for field: String) -> String? {
        guard touched.contains(field) else { return nil }
        return unmet.first { $0.field == field }?.message
    }

    @State private var selection: AgentProfile = BuiltInAgents.build
    @State private var isCustom = false
    @State private var customName = ""
    @State private var customInstructions = ""
    @State private var model = AgentConfigDocument().model
    @State private var effort = AgentConfigDocument().effort
    /// The id of the custom persona this step session has already added to
    /// `agents`, if any — reused on subsequent commits so Back-then-Continue
    /// updates the existing entry instead of appending a duplicate.
    @State private var customProfileID: UUID?
    /// Custom-persona fields the user has typed in — see `message(for:)`.
    @State private var touched: Set<String> = []

    var body: some View {
        let tokens = environment.themeManager.hostSkin

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s18) {
                    intro(tokens: tokens)
                    builtins(tokens: tokens)
                    custom(tokens: tokens)
                    modelAndEffort(tokens: tokens)
                }
                .padding(skin.size.s20)
                // FILLS the group, exactly as the Home step's folder listing
                // does. Capping the whole column instead left every panel hard
                // against the left edge with a void beside it — the layout read
                // as broken rather than as composed, because the empty space was
                // INSIDE the group rather than around it.
                //
                // Prose within the column is capped individually; see the
                // section hints.
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SetupStepFooter(
                coordinator: coordinator,
                isPrimaryDisabled: !unmet.isEmpty
            ) {
                commit()
                coordinator.advance()
            }
        }
        .onAppear {
            model = SetupAssistant.defaultModel(
                connections: environment.connectionStore.connections,
                activeConnectionID: environment.agentConfigStore.activeConnectionID)
            environment.agentConfigStore.setModel(model)
        }
        .onChange(of: effort) { _, newValue in
            environment.agentConfigStore.setEffort(newValue)
        }
    }

    /// Effort only means anything to `ClaudeProvider` (see
    /// `AgentSession.effortString`); Settings gates its own effort picker on
    /// `active?.kind == .claude` (SageSettingsView+Sections.swift
    /// ~line 91), so this step mirrors that rather than showing a control
    /// that silently does nothing for OpenAI/Ollama/Groq/etc.
    private var activeConnectionIsClaude: Bool {
        let connections = environment.connectionStore.connections
        let active =
            environment.agentConfigStore.activeConnectionID.flatMap { id in
                connections.first { $0.id == id }
            } ?? connections.first
        return active?.kind == .claude
    }

    private func intro(tokens: AinkradSkin) -> some View {
        Text(
            "Ainkrad ships with two agents, Plan and Build. Confirm which one starts "
                + "active — or write your own persona instead. You can add and edit more "
                + "agents later."
        )
        .font(AinkradFont.display(12))
        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o60))
        .fixedSize(horizontal: false, vertical: true)
        // Prose is capped even though the column fills, so the agent rows
        // below can use the room without the intro running with them.
        .frame(
            maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
            alignment: .leading)
    }

    private func builtins(tokens: AinkradSkin) -> some View {
        AinkradSettingsPanel(
            title: "Starting agent",
            hint: "Plan and Build ship built-in — pick which one is active when you arrive."
        ) {
            ForEach(BuiltInAgents.all) { agent in
                builtinRow(agent, tokens: tokens)
            }
        }
    }

    private func builtinRow(_ agent: AgentProfile, tokens: AinkradSkin) -> some View {
        let isSelected = !isCustom && selection.id == agent.id
        // A raw `Button`: the agent's instructions are the point of the row and
        // run to several lines, and `AinkradListRow` truncates its subtitle to one.
        return Button {  // design-lint: allow raw-control kit gap, list row with multi-line detail
            isCustom = false
            selection = agent
        } label: {
            HStack(alignment: .top, spacing: skin.size.s10) {
                Image(systemName: agent.icon)
                    .font(skin.font(AinkradFontToken(sizeKey: "t13", scaled: false)))
                    .foregroundStyle(isSelected ? tokens.color(\.accentSecondary) : tokens.color(\.foreground).opacity(skin.opacity.o60))
                VStack(alignment: .leading, spacing: skin.spacing.xs) {
                    Text(agent.name)
                        .font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
                    Text(agent.instructions)
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o50))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: skin.spacing.sm)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(skin.font(AinkradFontToken(sizeKey: "t14", scaled: false)))
                        .foregroundStyle(tokens.color(\.accentSecondary))
                }
            }
            .padding(skin.spacing.md)
            .background(ChamferShape(cut: skin.radius.md).fill(tokens.color(\.surfaceElevated).opacity(skin.opacity.o50)))
            .overlay(
                ChamferShape(cut: skin.radius.md)
                    .strokeBorder(
                        isSelected ? tokens.color(\.accentSecondary).opacity(skin.opacity.o50) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func custom(tokens: AinkradSkin) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            AinkradListRow(
                isSelected: isCustom,
                onTap: { isCustom = true },
                leading: {
                    Image(systemName: "sparkles")
                        .font(skin.font(AinkradFontToken(sizeKey: "t12", scaled: false)))
                        .foregroundStyle(
                            isCustom ? tokens.color(\.accentSecondary) : tokens.color(\.foreground).opacity(skin.opacity.o60))
                },
                title: "Write your own persona instead",
                trailing: {
                    if isCustom {
                        Image(systemName: "checkmark.circle.fill")
                            .font(skin.font(AinkradFontToken(sizeKey: "t14", scaled: false)))
                            .foregroundStyle(tokens.color(\.accentSecondary))
                    }
                }
            )

            if isCustom {
                // Each unmet requirement is rendered directly under the field
                // it is about. A disabled Continue at the far corner with no
                // explanation is the failure mode this avoids.
                VStack(alignment: .leading, spacing: skin.spacing.xs) {
                    AinkradTextField(text: $customName, placeholder: "Name (e.g. Scribe)")
                        .onChange(of: customName) { _, _ in touched.insert("personaName") }
                    if let message = message(for: "personaName") {
                        SetupRequirementNote(message: message, tokens: tokens)
                            .accessibilityIdentifier("setup.assistant.personaName.requirement")
                    }
                }
                VStack(alignment: .leading, spacing: skin.spacing.xs) {
                    AinkradTextField(text: $customInstructions, placeholder: "Instructions")
                        .onChange(of: customInstructions) { _, _ in
                            touched.insert("personaInstructions")
                        }
                    if let message = message(for: "personaInstructions") {
                        SetupRequirementNote(message: message, tokens: tokens)
                            .accessibilityIdentifier("setup.assistant.personaInstructions.requirement")
                    }
                }
            }
        }
    }

    private func modelAndEffort(tokens: AinkradSkin) -> some View {
        AinkradSettingsPanel(
            title: "Model",
            hint: "Which model handles requests, and how much effort it spends on each one."
        ) {
            HStack(spacing: skin.size.s18) {
                VStack(alignment: .leading, spacing: skin.size.s6) {
                    Text("Model").font(AinkradFont.display(11)).foregroundStyle(
                        tokens.color(\.foreground).opacity(skin.opacity.o50))
                    Text(model).font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
                }
                if activeConnectionIsClaude {
                    VStack(alignment: .leading, spacing: skin.size.s6) {
                        Text("Effort").font(AinkradFont.display(11)).foregroundStyle(
                            tokens.color(\.foreground).opacity(skin.opacity.o50))
                        AinkradSegmentedPicker(
                            items: Self.efforts,
                            selection: $effort,
                            label: { $0.capitalized }
                        )
                        .fixedSize()
                    }
                }
            }
        }
    }

    private func commit() {
        let profile: AgentProfile
        if isCustom {
            // Reuse the same id across Back-then-Continue within this step
            // session so `SetupAssistant.apply` updates the existing custom
            // persona instead of appending a duplicate.
            let id = customProfileID ?? UUID()
            customProfileID = id
            profile = AgentProfile(
                id: id,
                name: customName.trimmingCharacters(in: .whitespacesAndNewlines),
                instructions: customInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
                toolPolicy: .all)
        } else {
            profile = selection
        }
        SetupAssistant.apply(
            profile: profile, model: model, effort: effort,
            agents: environment.agentStore, config: environment.agentConfigStore)
    }
}
