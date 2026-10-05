import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

/// The delete-workspace confirmation, in the app's HUD language: a hazard
/// emblem inside targeting brackets, an energy-seam divider, and a glowing
/// destructive action. Shown only when the workspace still has apps open.
struct DeleteWorkspaceConfirmation: View {
    let workspaceName: String
    let appCount: Int
    let tokens: DesignTokens
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var deleteHover = false
    @State private var cancelHover = false

    private let danger = Color(hex: "E5484D")

    var body: some View {
        VStack(spacing: 0) {
            emblem
                .padding(.top, 26)
                .padding(.bottom, 16)

            Text("Delete “\(workspaceName)”?")
                .font(AinkradFont.display(16, weight: .semibold))
                .foregroundStyle(tokens.foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)

            Text(
                "\(appCount) app\(appCount == 1 ? "" : "s") still running here — \(appCount == 1 ? "its session" : "their sessions") will end."
            )
            .font(AinkradFont.display(12))
            .foregroundStyle(tokens.foreground.opacity(0.62))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 26)
            .padding(.top, 7)

            LinearGradient(colors: [.clear, danger.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .padding(.horizontal, 22)
                .padding(.top, 20)

            HStack(spacing: 10) {
                cancelButton
                deleteButton
            }
            .padding(20)
        }
        .frame(width: 360)
        .background(tokens.background.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [danger.opacity(0.55), tokens.accentPrimary.opacity(0.2)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
        .overlay(
            TargetingBrackets(length: 13)
                .stroke(danger.opacity(0.4), lineWidth: 1.5)
                .padding(-3)
        )
        .shadow(color: danger.opacity(0.28), radius: 30)
        .shadow(color: .black.opacity(0.55), radius: 24, y: 8)
    }

    private var emblem: some View {
        ZStack {
            Circle().fill(danger.opacity(0.12)).frame(width: 54, height: 54)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(danger)
                .shadow(color: danger.opacity(0.7), radius: 9)
        }
        .overlay(
            TargetingBrackets(length: 9)
                .stroke(danger.opacity(0.85), lineWidth: 1.3)
                .frame(width: 62, height: 62)
        )
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("Cancel")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(cancelHover ? 0.95 : 0.75))
                .frame(width: 108, height: 32)
                .background(tokens.surfaceElevated.opacity(cancelHover ? 0.95 : 0.75))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).strokeBorder(
                        tokens.accentPrimary.opacity(cancelHover ? 0.5 : 0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { cancelHover = $0 }
    }

    private var deleteButton: some View {
        Button(action: onConfirm) {
            Text("Delete")
                .font(AinkradFont.display(12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 108, height: 32)
                .background(danger.opacity(deleteHover ? 1 : 0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(danger, lineWidth: 1))
                .overlay(
                    TargetingBrackets(length: 8)
                        .stroke(deleteHover ? .white.opacity(0.9) : .clear, lineWidth: 1.3)
                        .padding(3)
                )
                .shadow(color: danger.opacity(deleteHover ? 0.75 : 0.45), radius: deleteHover ? 14 : 10)
        }
        .buttonStyle(.plain)
        .onHover { deleteHover = $0 }
        .animation(.easeOut(duration: 0.12), value: deleteHover)
    }
}
