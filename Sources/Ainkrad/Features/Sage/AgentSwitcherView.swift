import AinkradAppKit
import AinkradHostRuntime
// Sources/Ainkrad/Features/Sage/AgentSwitcherView.swift
import SwiftUI

/// The composer's leftmost pill: switches the active `AgentProfile` (Plan /
/// Build / any custom agent). Uses the Cardinal-HUD `AinkradSelect` — a custom
/// floating-panel dropdown, never a native `Picker`/`Menu` — matching the
/// connection·model and permission-mode pills beside it (M7 Slice 5a Task 5).
struct AgentSwitcherView: View {
    let store: AgentStore
    let tokens: DesignTokens

    var body: some View {
        AinkradSelect(
            items: store.agents.map(\.id),
            selection: Binding(get: { store.active.id }, set: { store.setActive($0) }),
            label: { id in store.agents.first { $0.id == id }?.name ?? "Agent" }
        )
        .fixedSize()
        .help("Active Agent — press Tab in the composer to cycle")
    }
}
