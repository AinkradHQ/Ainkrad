import Foundation

// MARK: - Copy → verify

/// The single publish primitive every row strategy in `VaultMigration` goes
/// through, plus the two filesystem checks it relies on.
extension VaultMigration {
    /// Copies one file and verifies what landed against what was read. A short
    /// write — a full disk part-way through — is silent data loss otherwise, so a
    /// failed verification removes the partial destination and throws. The SOURCE
    /// is never touched.
    ///
    /// `verify` is injectable so a test can exercise the failure branch without
    /// filling a disk.
    static func copyVerified(
        from source: URL, to target: URL,
        verify: (URL, URL) throws -> Bool = contentsMatch
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        // Everything lands on a scratch path THIS call created, in the target's own
        // directory (same volume). Cleanup can then only ever remove our own scratch
        // file — never a pre-existing vault entry — which is true by construction and
        // does not depend on an earlier "does the target exist?" observation that a
        // dangling symlink or a concurrent writer could invalidate.
        let scratch = target.deletingLastPathComponent()
            .appendingPathComponent(".ainkrad-migrate-\(UUID().uuidString)")
        func discardScratch() { try? fm.removeItem(at: scratch) }

        do {
            try fm.copyItem(at: source, to: scratch)
        } catch {
            discardScratch()
            throw error
        }

        // Symlinks are copied as links; comparing the link targets, not the
        // (possibly absent) files they point at, is the only meaningful check.
        let isSymlink =
            (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]))?
            .isSymbolicLink ?? false
        if isSymlink {
            let a = try? fm.destinationOfSymbolicLink(atPath: source.path)
            let b = try? fm.destinationOfSymbolicLink(atPath: scratch.path)
            guard a != nil, a == b else {
                discardScratch()
                throw CocoaError(.fileWriteUnknown)
            }
        } else {
            let matched: Bool
            do {
                matched = try verify(source, scratch)
            } catch {
                discardScratch()
                throw error
            }
            guard matched else {
                discardScratch()
                throw CocoaError(.fileWriteUnknown)
            }
        }

        // `linkItem` is `link(2)`: it fails with EEXIST if ANYTHING is at `target`
        // — including a dangling symlink, which `fileExists` reports as absent — and
        // it never follows or replaces it. That makes "publish only into an empty
        // slot" atomic rather than a check followed by a hopeful write.
        do {
            try fm.linkItem(at: scratch, to: target)
        } catch {
            discardScratch()
            throw error
        }
        discardScratch()
    }

    /// Existence that does not lie about symlinks: `FileManager.fileExists` follows
    /// links and so reports a DANGLING symlink as absent. `attributesOfItem` is
    /// `lstat`-shaped — it sees the link itself. Every "is this destination slot
    /// occupied?" decision in this file must use this, because treating a dangling
    /// symlink as an empty slot is how a migration ends up destroying a vault entry
    /// it did not create.
    static func entryExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Byte-for-byte comparison, streamed in chunks so a large plugin bundle is
    /// never held in memory twice.
    static func contentsMatch(_ a: URL, _ b: URL) throws -> Bool {
        let fm = FileManager.default
        let sizeA = (try fm.attributesOfItem(atPath: a.path)[.size] as? NSNumber)?.intValue
        let sizeB = (try fm.attributesOfItem(atPath: b.path)[.size] as? NSNumber)?.intValue
        guard sizeA == sizeB else { return false }

        let handleA = try FileHandle(forReadingFrom: a)
        defer { try? handleA.close() }
        let handleB = try FileHandle(forReadingFrom: b)
        defer { try? handleB.close() }

        let chunk = 1 << 20
        while true {
            let dataA = try handleA.read(upToCount: chunk) ?? Data()
            let dataB = try handleB.read(upToCount: chunk) ?? Data()
            guard dataA == dataB else { return false }
            if dataA.isEmpty { return true }
        }
    }
}
