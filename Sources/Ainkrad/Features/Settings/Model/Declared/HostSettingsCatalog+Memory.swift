import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import AppKit
import SwiftUI

/// Memory as DECLARED rows: each memory file opens in your editor (a document
/// is not a setting), and each autonomous write is a row with Undo.
@MainActor
extension HostSettingsCatalog {
    static func memoryGroups(_ environment: AppEnvironment, page: SettingsPath) -> [SettingsGroup] {
        let files = page.appending("index")
        guard let service = environment.memoryService else {
            return [
                SettingsGroup(
                    path: files, title: "Memory",
                    fields: [
                        SettingsField(
                            path: files.appending("unavailable"), label: "Memory unavailable",
                            help: "The memory index couldn't be opened this launch, so the assistant is running "
                                + "memory-less for now. Restart Ainkrad to try again.",
                            keywords: ["memory"], kind: .shortcut(.constant("Off")))
                    ])
            ]
        }
        let store = service.store
        var fileFields: [SettingsField] = MemoryFile.allCases.map { file in
            let text = store.read(file)
            let lines = text.split(separator: "\n").count
            return SettingsField(
                path: files.appending(file.rawValue), label: file.rawValue,
                help: text.isEmpty ? "Empty — nothing learned here yet." : "\(lines) line\(lines == 1 ? "" : "s")",
                keywords: ["memory", "remember", file.rawValue.lowercased()],
                kind: .action(title: "Open") {
                    let url = store.url(for: file)
                    if !FileManager.default.fileExists(atPath: url.path) { store.write("", to: file) }
                    NSWorkspace.shared.open(url)
                })
        }
        fileFields.append(
            SettingsField(
                path: files.appending("reindex"), label: "Reindex memory",
                help: "After editing a memory file outside Ainkrad, so recall sees the change.",
                keywords: ["memory", "reindex", "recall", "index"],
                kind: .action(title: "Reindex") { service.rebuildIndex() }))

        let log = page.appending("log")
        let entries = service.log.entries()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let logFields: [SettingsField] =
            entries.isEmpty
            ? [
                SettingsField(
                    path: log.appending("empty"), label: "Nothing learned yet",
                    help: "Autonomous writes — from chats, /remember and consolidation — appear here.",
                    kind: .shortcut(.constant("—")))
            ]
            : entries.map { entry in
                let first =
                    entry.addedText.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? entry.addedText
                return SettingsField(
                    path: log.appending(entry.id.uuidString),
                    label: first.isEmpty ? "(empty)" : (first.count > 90 ? String(first.prefix(90)) + "…" : first),
                    help: "\(entry.file) · \(entry.provenance.rawValue) · \(formatter.string(from: entry.date))",
                    keywords: ["memory", "learned", "undo"],
                    kind: .action(title: "Undo") { service.log.undo(entry.id) })
            }
        return [
            SettingsGroup(
                path: files, title: "Memory",
                footerNote: "What the assistant remembers between sessions.", fields: fileFields),
            SettingsGroup(
                path: log, title: "Learned",
                footerNote: "Every memory write the assistant made on its own, with per-entry undo.",
                fields: logFields),
        ]
    }
}
