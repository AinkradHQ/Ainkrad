import Foundation
import Testing

@testable import Ainkrad

@Suite("File formatting")
struct FileFormattingTests {
    private func entry(_ name: String, dir: Bool = false) -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/x/\(name)"), name: name, isDirectory: dir,
            isSymlink: false, isHidden: false, size: 0, modified: Date())
    }

    @Test("directories show no size")
    func directorySize() {
        #expect(formattedSize(0, isDirectory: true) == "—")
    }

    @Test("byte sizes are human readable")
    func byteSizes() {
        // Don't assert ByteCountFormatter's exact zero string — it is
        // locale- and OS-dependent ("Zero KB" / "0 bytes"). Assert the
        // properties we actually depend on.
        #expect(!formattedSize(0, isDirectory: false).isEmpty)
        #expect(formattedSize(1_500_000, isDirectory: false).contains("MB"))
        #expect(formattedSize(2_000, isDirectory: false) != formattedSize(2_000_000, isDirectory: false))
    }

    @Test("today's files show a time, older files show a date")
    func dateFormatting() {
        // Anchor at LOCAL noon, not a fixed epoch: an epoch constant lands
        // just after midnight in some time zones, where "an hour earlier" is
        // genuinely yesterday and this test would fail on the calendar rather
        // than on the code.
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 12))!
        let earlierToday = now.addingTimeInterval(-3600)
        let lastYear = calendar.date(from: DateComponents(year: 2022, month: 10, day: 10, hour: 12))!

        // Same-day renders as a time, older renders as a date carrying a year.
        #expect(formattedDate(earlierToday, now: now) != formattedDate(lastYear, now: now))
        #expect(!formattedDate(earlierToday, now: now).contains("2023"))
        #expect(formattedDate(lastYear, now: now).contains("2022"))
    }

    @Test("icons distinguish directories from files")
    func icons() {
        #expect(iconName(for: entry("d", dir: true)) == "folder")
        #expect(iconName(for: entry("a.swift")) == "swift")
        #expect(iconName(for: entry("a.png")) == "photo")
        #expect(iconName(for: entry("a.unknownext")) == "doc")
    }
}
