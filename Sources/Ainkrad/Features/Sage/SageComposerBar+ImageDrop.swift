import AinkradAppKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Image/file drag-and-drop handling for `SageComposerBar` (M7 finalize
/// Wave D, D2 — extracted verbatim, no behavior change).
extension SageComposerBar {
    /// Attaches a dropped/pasted image or file URL. Accepts both `.image`
    /// (e.g. a Finder image drag, which vends `NSImage`-backed data) and
    /// `.fileURL` (a plain file path drag) — `ImageAttachment.from(fileURL:)`
    /// sniffs the actual bytes either way, so a non-image file URL is
    /// rejected rather than silently misattached.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                        let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }
                    Task { @MainActor in
                        if AudioFileValidator.allowedExtensions.contains(url.pathExtension.lowercased()) {
                            await transcribeDroppedAudio(url)
                        } else {
                            attach(fileURL: url)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in attach(imageData: data) }
                }
            }
        }
        return handled
    }

    func attach(fileURL: URL) {
        do {
            let attachment = try ImageAttachment.from(fileURL: fileURL)
            attachAndWarn(attachment)
        } catch {
            toastCenter.show("Couldn't attach \(fileURL.lastPathComponent) as an image.", status: .danger)
        }
    }

    /// Audio-file drop (M7 Slice 8 Task 14) — routes a dropped fileURL whose
    /// extension `AudioFileValidator` allows to `fileCoordinator.transcribe`,
    /// inserting the resulting transcript into the draft. Runs INSIDE the
    /// same `handleDrop` provider loop Slice 5 established; non-audio file
    /// URLs keep taking the `attach(fileURL:)` path above unchanged.
    func transcribeDroppedAudio(_ url: URL) async {
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        do {
            let text = try await environment.voiceService.fileCoordinator.transcribe(
                fileURL: url, byteCount: byteCount, progress: { _ in }
            )
            draft = draft.isEmpty ? text : draft + "\n\n" + text
        } catch {
            toastCenter.show("Couldn't transcribe \(url.lastPathComponent).", status: .danger)
        }
    }

    func attach(imageData: Data) {
        guard let mediaType = ImageAttachment.sniffMediaType(imageData), imageData.count <= ImageAttachment.maxBytes
        else {
            toastCenter.show("That image couldn't be attached (unsupported format or too large).", status: .danger)
            return
        }
        attachAndWarn(ImageAttachment(mediaType: mediaType, base64: imageData.base64EncodedString()))
    }

    /// Appends the attachment, then surfaces (never blocks on) a vision-gate
    /// warning if the current model can't accept images — Task 22's spec
    /// explicitly calls for a warning, not a hard block.
    func attachAndWarn(_ attachment: ImageAttachment) {
        pendingImages.append(attachment)
        let modelID = session.activeModelIDForCommands()
        if let warning = visionGate(model: modelID, catalog: environment.modelCatalog, hasImage: true) {
            toastCenter.show(warning, status: .warning)
        }
    }

    var attachmentChips: some View {
        HStack(spacing: 6) {
            ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, attachment in
                AinkradChip(label: attachment.mediaType, systemName: "photo") {
                    pendingImages.remove(at: index)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
