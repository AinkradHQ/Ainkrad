import AinkradSignal

extension RoutingRules {
    /// Every source with at least one override of any kind — what "Reset all
    /// overrides" clears, and which app sources the Sources tab lists even
    /// before they have emitted anything.
    var configuredSources: Set<SignalSource> {
        var out = mutedSources
        out.formUnion(sourceOverrides.keys)
        out.formUnion(sourceKindOverrides.keys.map(\.source))
        out.formUnion(interruptFloor.keys)
        out.formUnion(soundOverride.keys)
        out.formUnion(urgentBypass)
        return out
    }
}
