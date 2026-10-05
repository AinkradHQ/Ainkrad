import AinkradAppKit
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("AppAppearanceStore")
@MainActor
struct AppAppearanceStoreTests {
    @Test func defaultsPerAppAreOpaqueNoBlur() {
        let store = AppAppearanceStore(persistence: InMemoryPersistenceStore())
        #expect(store.surfaceOpacity("terminal") == 1.0)
        #expect(store.blurEnabled("terminal") == false)
        #expect(store.blurEnabled("gitmage") == false)
    }

    @Test func blurIsIndependentPerApp() {
        let store = AppAppearanceStore(persistence: InMemoryPersistenceStore())
        store.setBlurEnabled("terminal", true)
        #expect(store.blurEnabled("terminal") == true)
        #expect(store.blurEnabled("gitmage") == false)
    }

    @Test func clampsSurfaceOpacityPerApp() {
        let store = AppAppearanceStore(persistence: InMemoryPersistenceStore())
        store.setSurfaceOpacity("sage", 1.7)
        #expect(store.surfaceOpacity("sage") == 1.0)
        store.setSurfaceOpacity("sage", -0.4)
        #expect(store.surfaceOpacity("sage") == 0.0)
        store.setSurfaceOpacity("sage", 0.55)
        #expect(store.surfaceOpacity("sage") == 0.55)
    }

    @Test func persistsAcrossReload() {
        let persistence = InMemoryPersistenceStore()
        let store = AppAppearanceStore(persistence: persistence)
        store.setSurfaceOpacity("sage", 0.6)
        store.setBlurEnabled("terminal", true)

        let reloaded = AppAppearanceStore(persistence: persistence)
        #expect(reloaded.surfaceOpacity("sage") == 0.6)
        #expect(reloaded.blurEnabled("terminal") == true)
    }

    @Test func migratesLegacyAssistantDocumentIntoAssistantEntry() {
        let persistence = InMemoryPersistenceStore()
        // Seed the Slice-2c Sage-only document, then build the new store.
        persistence.save(LegacyAssistantAppearanceDocument(surfaceOpacity: 0.4, blurEnabled: true))
        let store = AppAppearanceStore(persistence: persistence)
        #expect(store.surfaceOpacity("sage") == 0.4)
        #expect(store.blurEnabled("sage") == true)
    }

    @Test("presentation override round-trips and defaults to nil")
    func presentationOverrideRoundTrips() {
        let store = AppAppearanceStore(persistence: InMemoryPersistenceStore())
        #expect(store.presentationOverride("leyline") == nil)
        store.setPresentationOverride("leyline", .overlay)
        #expect(store.presentationOverride("leyline") == .overlay)
        store.setPresentationOverride("leyline", nil)
        #expect(store.presentationOverride("leyline") == nil)
    }
}

@Suite("SageApp.surfaceFill")
@MainActor
struct SageSurfaceFillTests {
    @Test func opaqueAtFullOpacityReturnsNil() {
        #expect(SageApp.surfaceFill(opacity: 1.0, base: .white) == nil)
    }

    @Test func translucentBelowFullOpacityReturnsAColor() {
        #expect(SageApp.surfaceFill(opacity: 0.5, base: .white) != nil)
        #expect(SageApp.surfaceFill(opacity: 0.0, base: .white) != nil)
    }
}
