import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

/// Share flow for `SageRootView` — mirrors `SageRootView+Export.swift`.
/// Renders a self-contained HTML artifact to disk, reveals it in Finder, and
/// copies its `file://` link to the clipboard. Reuses the same redaction field.
extension SageRootView {
    var shareModalContent: some View {
        return VStack(alignment: .leading, spacing: skin.spacing.md) {
            Text("Share session")
                .font(AinkradFont.display(14, weight: .semibold))
                .foregroundStyle(theme.foreground)
            Text("Strings to redact, comma-separated (optional)")
                .font(AinkradFont.display(11))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o60))
            AinkradTextField(text: $redactionsText, placeholder: "e.g. sk-live-…, jane@example.com")

            HStack {
                AinkradButton(title: "Cancel", style: .ghost) { isShareModalPresented = false }
                Spacer(minLength: 8)
                AinkradButton(title: "Create artifact…", style: .primary) { performShare() }
            }
        }
    }

    func performShare() {
        isShareModalPresented = false
        let coordinator = SessionShareCoordinator(store: environment.sessionShareStore)
        do {
            let firstUser = environment.agentSession.messages.first { $0.role == .user }?.text ?? "Session"
            // Redact BEFORE truncating: a secret straddling the 60-char boundary
            // would otherwise leave an unmatched partial secret in the title.
            let redactions = RedactionList.parse(redactionsText)
            let safeTitle = String(RedactionList.apply(redactions, to: firstUser).prefix(60))
            let out = try coordinator.shareCurrentSession(
                messages: environment.agentSession.messages,
                title: safeTitle,
                redactionsText: redactionsText)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(out.clipboardLink, forType: .string)
            NSWorkspace.shared.activateFileViewerSelecting([out.record.fileURL])
            toastCenter.show("Created a shareable artifact; link copied.", status: .success)
        } catch {
            toastCenter.show("Couldn't create the share artifact.", status: .warning)
        }
    }
}
