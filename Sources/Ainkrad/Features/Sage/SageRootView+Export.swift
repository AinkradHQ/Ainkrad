import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

/// Export/redaction flow for `SageRootView` (relocated from
/// `SageComposerBar+Export.swift` so the modal presents over the full
/// Sage surface instead of the composer strip — see
/// `SageRootView.swift`'s `.ainkradModal` block. Extracted verbatim, no
/// behavior change). The strip entry point still lives in the `•••` overflow
/// panel (`SageComposerBar+Overflow.swift`), which sets
/// `isExportModalPresented` through its `@Binding`; this extension owns the
/// modal + export.
extension SageRootView {
    /// Redaction/confirm modal content. Rendering + writing happens on
    /// confirm (`performExport`): `ConversationExporter.export` runs with the
    /// user's comma-separated redaction strings, the result is copied to the
    /// clipboard AND written to a user-chosen file via `NSSavePanel`.
    var exportModalContent: some View {
        return VStack(alignment: .leading, spacing: skin.spacing.md) {
            Text("Export conversation")
                .font(AinkradFont.display(14, weight: .semibold))
                .foregroundStyle(theme.foreground)
            Text("Strings to redact, comma-separated (optional)")
                .font(AinkradFont.display(11))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o60))
            AinkradTextField(text: $redactionsText, placeholder: "e.g. sk-live-…, jane@example.com")

            HStack {
                AinkradButton(title: "Cancel", style: .ghost) { isExportModalPresented = false }
                Spacer(minLength: 8)
                AinkradButton(title: "Export…", style: .primary) { performExport() }
            }
        }
    }

    func performExport() {
        let redactions = RedactionList.parse(redactionsText)

        let rendered = ConversationExporter.export(
            environment.agentSession.messages, format: .markdown, redactions: redactions)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rendered, forType: .string)

        isExportModalPresented = false

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "conversation.md"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try rendered.write(to: url, atomically: true, encoding: .utf8)
                toastCenter.show("Exported the conversation to \(url.lastPathComponent).", status: .success)
            } catch {
                toastCenter.show("Copied to clipboard, but couldn't write the file.", status: .warning)
            }
        }
        toastCenter.show("Copied the transcript to your clipboard.", status: .success)
    }
}
