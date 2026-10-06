// design-lint: allow-file raw-color token-gap colors.trafficLight — the full-screen window controls
import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

/// The top edge of the screen — not a bar. The system traffic lights and
/// the clickable workspace dots float directly on the sky, with no
/// background tint and no separator, so the title-bar region is seamlessly
/// part of the workspace.
///
/// NOTE: the workspace dots intentionally supersede ADR-0008's
/// "no persistent workspace indicator" — approved as part of the
/// OS-direction visual redesign (clickable, brand-diamond styling).
struct HUDBar: View {
    /// The bar's own height, named so anything anchoring beneath it can read
    /// the number instead of copying it. The bell dropdown used a hardcoded
    /// 34 — this height plus a gap — which would have drifted the moment the
    /// bar changed.
    static let height: CGFloat = 30

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    @State private var statusMonitor = SystemStatusMonitor()

    /// The system traffic lights vacate the leading region in full-screen —
    /// show the status bar there instead, gated by the Settings toggle
    /// (AIN-109). `false` in windowed mode, where this region stays exactly
    /// as it was.
    private var showsStatusBar: Bool {
        environment.isFullScreen && environment.generalSettingsStore.showFullScreenStatusBar
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        HStack(spacing: skin.spacing.md) {
            // In full screen the system traffic lights are suppressed (they'd
            // drag the OS titlebar over this bar), so we host our own to the
            // left of the clock — hidden by default, revealed while the pointer
            // is at the top edge (`isTopBarRevealed`), Xcode-style.
            if environment.isFullScreen, environment.isTopBarRevealed {
                WindowControlsView()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if showsStatusBar {
                FullScreenStatusBarView(monitor: statusMonitor)
            }

            // Left side otherwise empty — the system traffic lights occupy
            // this region of the fused title bar in windowed mode.
            Spacer()

            if let center = environment.signalCenter {
                SignalBellButton(
                    unread: center.totalUnread,
                    isMuted: center.rules.suppression.isSuppressing(at: Date()),
                    arrivalToken: center.arrivalToken,
                    tokens: tokens
                ) {
                    environment.isSignalDropdownPresented.toggle()
                }
            }

            workspaceDots(tokens: tokens)
        }
        .padding(.horizontal, skin.size.s14)
        .frame(height: Self.height)
        .contentShape(Rectangle())
        // Reveal the traffic lights the moment the pointer is anywhere in the
        // status-bar strip, and keep them while it stays — hover tracking is
        // immediate and stateful, unlike a motion-only mouse monitor that the
        // menu-bar zone also contends for. Only meaningful in full screen.
        .onHover { hovering in
            guard environment.isFullScreen else { return }
            environment.isTopBarRevealed = hovering
        }
        .animation(.easeOut(duration: skin.motion.durations.d0_16), value: environment.isTopBarRevealed)
        // Only run the monitor's timer/NWPathMonitor while the bar is
        // actually shown, so full-screen + the toggle both gate the cost —
        // `initial: true` also starts it if the bar is already visible when
        // `HUDBar` first appears.
        .onChange(of: showsStatusBar, initial: true) { _, isVisible in
            if isVisible {
                statusMonitor.start()
            } else {
                statusMonitor.stop()
            }
        }
    }

    /// One diamond per workspace — the brand's diamond accent (the mark
    /// inside the chevron), not a generic dot. The active one glows in
    /// accentSecondary; clicking any switches to it.
    private func workspaceDots(tokens: DesignTokens) -> some View {
        let manager = environment.workspaceManager

        return HStack(spacing: skin.spacing.sm) {
            ForEach(Array(manager.workspaces.enumerated()), id: \.element.id) { index, workspace in
                let isActive = workspace.id == manager.activeWorkspaceID

                // The label is the workspace's mark; no kit button takes a
                // custom label.
                Button {  // design-lint: allow raw-control kit gap, content label
                    manager.switchTo(workspace.id)
                } label: {
                    Group {
                        if workspace.isMain {
                            // The home island wears the chevron mark.
                            AinkradBrandChevron()
                                .fill(isActive ? tokens.accentSecondary : tokens.foreground.opacity(skin.opacity.o35))
                                .frame(width: isActive ? 10 : 8, height: isActive ? 8.5 : 7)
                        } else {
                            Rectangle()
                                .fill(isActive ? tokens.accentSecondary : tokens.foreground.opacity(skin.opacity.o28))
                                .frame(width: isActive ? 7 : 5, height: isActive ? 7 : 5)
                                .rotationEffect(.degrees(45))
                        }
                    }
                    .shadow(
                        color: isActive ? tokens.accentSecondary.opacity(skin.opacity.o90) : .clear,
                        radius: skin.size.s4
                    )
                    .frame(width: skin.size.s12, height: skin.size.s11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(workspace.name)\(index < 9 ? " — ⌘\(index + 1)" : "")")
            }
        }
        .animation(.easeOut(duration: skin.motion.durations.d0_18), value: manager.activeWorkspaceID)
    }
}

/// Full-screen stand-ins for the system traffic lights, hosted inside the
/// app's own top bar. The real window buttons are hidden in full screen (see
/// `KeyboardShortcutMonitor`) so the OS titlebar can't slide over our bar;
/// these carry the same three actions and show their glyphs on hover, matching
/// the native look.
private struct WindowControlsView: View {
    @Environment(\.ainkradSkin) private var skin
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: skin.spacing.sm) {
            control(
                color: Color(red: 1.0, green: 0.37, blue: 0.34),
                glyph: "xmark", help: "Close"
            ) { $0.performClose(nil) }
            control(
                color: Color(red: 1.0, green: 0.74, blue: 0.18),
                glyph: "minus", help: "Minimize"
            ) { $0.miniaturize(nil) }
            control(
                color: Color(red: 0.16, green: 0.79, blue: 0.25),
                glyph: "arrow.down.right.and.arrow.up.left",
                help: "Exit Full Screen"
            ) { $0.toggleFullScreen(nil) }
        }
        .onHover { isHovering = $0 }
    }

    private func control(
        color: Color, glyph: String, help: String,
        action: @escaping (NSWindow) -> Void
    ) -> some View {
        // The label is a drawn traffic light; no kit button takes a custom label.
        Button {  // design-lint: allow raw-control kit gap, content label
            if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first {
                action(window)
            }
        } label: {
            ZStack {
                Circle().fill(color)
                if isHovering {
                    Image(systemName: glyph)
                        .font(skin.font(AinkradFontToken(sizeKey: "t6_5", weight: "bold", scaled: false)))
                        .foregroundStyle(skin.color(.palette("black", skin.opacity.o55)))
                }
            }
            .frame(width: skin.size.s12, height: skin.size.s12)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
