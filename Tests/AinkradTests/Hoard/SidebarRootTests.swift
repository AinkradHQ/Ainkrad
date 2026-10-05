import Foundation
import Testing

@testable import Ainkrad

@Suite("Sidebar roots")
struct SidebarRootTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    @Test("home is first")
    func homeFirst() {
        let roots = standardRoots(home: home)
        #expect(roots.first?.id == "home")
        #expect(roots.first?.url == home)
    }

    @Test("includes the standard places under home")
    func standardPlaces() {
        let roots = standardRoots(home: home)
        let ids = roots.map(\.id)
        #expect(ids.contains("desktop"))
        #expect(ids.contains("documents"))
        #expect(ids.contains("downloads"))
        #expect(ids.contains("applications"))
        #expect(roots.first { $0.id == "downloads" }?.url == home.appendingPathComponent("Downloads"))
    }

    @Test("applications is absolute, not under home")
    func applicationsIsAbsolute() {
        let roots = standardRoots(home: home)
        #expect(roots.first { $0.id == "applications" }?.url == URL(fileURLWithPath: "/Applications"))
    }

    @Test("every root carries an SF Symbol name and unique id")
    func iconsAndIDs() {
        let roots = standardRoots(home: home)
        #expect(roots.allSatisfy { !$0.icon.isEmpty })
        #expect(Set(roots.map(\.id)).count == roots.count)
    }
}
