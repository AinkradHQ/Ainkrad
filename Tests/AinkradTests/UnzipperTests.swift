import Foundation
import Testing

@testable import Ainkrad

struct UnzipperTests {
    /// Zips a directory with `ditto -c -k` (test helper), then unzips it with
    /// the production DittoUnzipper and checks the contents survive.
    @Test("DittoUnzipper extracts a zip round-trip")
    func roundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = tmp.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "hello".data(using: .utf8)!.write(to: src.appendingPathComponent("a.txt"))

        let zip = tmp.appendingPathComponent("out.zip")
        let make = Process()
        make.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        make.arguments = ["-c", "-k", src.path, zip.path]
        try make.run()
        make.waitUntilExit()
        #expect(make.terminationStatus == 0)

        let dest = tmp.appendingPathComponent("dest")
        try DittoUnzipper().unzip(zip, to: dest)
        let extracted = try String(contentsOf: dest.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(extracted == "hello")
    }

    @Test("a zip with a path-traversal entry is rejected and writes nothing outside")
    func rejectsZipSlip() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let zip = root.appendingPathComponent("evil.zip")
        // Craft a zip whose single entry name is "../escape.txt" via python3.
        let py = "import zipfile;z=zipfile.ZipFile(r'\(zip.path)','w');z.writestr('../escape.txt','pwned');z.close()"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", "-c", py]
        try p.run()
        p.waitUntilExit()
        let dest = root.appendingPathComponent("out")
        #expect(throws: UnzipError.self) { try DittoUnzipper().unzip(zip, to: dest) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.txt").path))
    }

    @Test("a zip containing a symlink is rejected")
    func rejectsSymlink() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let payload = root.appendingPathComponent("payload")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: payload.appendingPathComponent("link").path, withDestinationPath: "/etc/hosts")
        let zip = root.appendingPathComponent("sym.zip")
        let c = Process()
        c.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        c.arguments = ["-c", "-k", "--keepParent", payload.path, zip.path]
        try c.run()
        c.waitUntilExit()
        let dest = root.appendingPathComponent("out")
        #expect(throws: UnzipError.self) { try DittoUnzipper().unzip(zip, to: dest) }
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }

    @Test("a normal bundle zip still extracts")
    func extractsNormal() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let payload = root.appendingPathComponent("payload")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: payload.appendingPathComponent("file.txt"))
        let zip = root.appendingPathComponent("ok.zip")
        let c = Process()
        c.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        c.arguments = ["-c", "-k", "--keepParent", payload.path, zip.path]
        try c.run()
        c.waitUntilExit()
        let dest = root.appendingPathComponent("out")
        try DittoUnzipper().unzip(zip, to: dest)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("payload/file.txt").path))
    }
}
