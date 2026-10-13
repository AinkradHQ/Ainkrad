import AppKit
import SwiftUI
import Testing
import WebKit

@testable import Ainkrad

/// FD36: a focused plugin's `.keyboardShortcut` claim outranks a host chord.
@Suite("Plugin key claims")
@MainActor
struct PluginKeyClaimTests {
    private func offers(
        hostChord: Bool = true, pushToTalk: Bool = false, overlay: Bool = false,
        plugin: Bool = true, webView: Bool = false
    ) -> Bool {
        PluginKeyClaim.offers(
            isHostChord: hostChord, isPushToTalk: pushToTalk, isOverlayPresented: overlay,
            focusedPaneIsPlugin: plugin, webViewHasKeyboard: webView)
    }

    @Test func aHostChordIsOfferedToTheFocusedPlugin() {
        #expect(offers())
    }

    // Everything else already reaches the plugin through the normal path;
    // offering it early would only run the claim walk twice.
    @Test func nonHostChordsAreNotOffered() {
        #expect(!offers(hostChord: false))
    }

    // Built-in apps never claim: host chords act exactly as before.
    @Test func aBuiltInPaneNeverOutranksTheHost() {
        #expect(!offers(plugin: false))
    }

    // ⌘K / ⌘, must keep closing the overlay that owns the keyboard.
    @Test func anOverlayKeepsHostChordsForTheHost() {
        #expect(!offers(overlay: true))
    }

    // Hold gesture with its own key-up edge — never handed away.
    @Test func pushToTalkIsNeverOffered() {
        #expect(!offers(pushToTalk: true))
    }

    // A focused WKWebView takes every key equivalent for the page, which would
    // turn ⌘← / ⌘D into editing commands.
    @Test func aFocusedWebViewKeepsHostChordsForTheHost() {
        #expect(!offers(webView: true))
    }

    // The mechanism itself, off-screen: a zero-size claim button (the shape
    // Forge's `ShortcutLayer` uses) answers `claim`, an unclaimed chord does not.
    @Test func aZeroSizeKeyboardShortcutButtonClaimsTheChord() {
        var fired = 0
        let window = Self.window(
            NSHostingView(
                rootView: Button("Close Tab") { fired += 1 }
                    .keyboardShortcut("w", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
                    .frame(width: 200, height: 200)))
        defer { window.close() }

        #expect(PluginKeyClaim.claim(Self.commandKey("w", keyCode: 13), in: window))
        #expect(fired == 1)
        #expect(!PluginKeyClaim.claim(Self.commandKey("1", keyCode: 18), in: window))
        #expect(fired == 1)
    }

    @Test func detectsAWebViewHoldingTheKeyboard() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let webView = WKWebView(frame: container.bounds)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        container.addSubview(webView)
        container.addSubview(field)
        let window = Self.window(container)
        defer { window.close() }

        _ = window.makeFirstResponder(field)
        #expect(!PluginKeyClaim.webViewHasKeyboard(in: window))
        _ = window.makeFirstResponder(webView)
        #expect(PluginKeyClaim.webViewHasKeyboard(in: window))
    }

    private static func window(_ content: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 200, height: 200),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return window
    }

    private static func commandKey(_ characters: String, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }
}
