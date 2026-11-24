import XCTest
@testable import SpaceLens

final class DiskScannerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("spacelens-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func write(_ rel: String, bytes: Int) throws {
        let url = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    private func allocated(_ rel: String) -> Int64 {
        var st = stat()
        lstat(dir.appendingPathComponent(rel).path, &st)
        return Int64(st.st_blocks) * 512
    }

    func testSizesMatchStat() throws {
        try write("a.bin", bytes: 3_000_000)
        try write("sub/b.bin", bytes: 1_500_000)
        try write("sub/deep/c.txt", bytes: 10)
        try write("sub/deep/d.txt", bytes: 5000)

        let root = try XCTUnwrap(DiskScanner().scan(path: dir.path))
        let expected = ["a.bin", "sub/b.bin", "sub/deep/c.txt", "sub/deep/d.txt"].map(allocated).reduce(0, +)
        XCTAssertEqual(root.size, expected)
        XCTAssertEqual(root.fileCount, 4)

        // Largest first.
        XCTAssertEqual(root.children.map(\.name), ["a.bin", "sub"])
        let sub = root.children[1]
        XCTAssertTrue(sub.isDir)
        XCTAssertEqual(sub.size, expected - allocated("a.bin"))
        XCTAssertEqual(sub.path, dir.resolvingSymlinksInPath().path + "/sub")
    }

    func testHardLinksCountedOnce() throws {
        try write("one.bin", bytes: 2_000_000)
        try FileManager.default.linkItem(at: dir.appendingPathComponent("one.bin"), to: dir.appendingPathComponent("two.bin"))
        let root = try XCTUnwrap(DiskScanner().scan(path: dir.path))
        XCTAssertEqual(root.size, allocated("one.bin"))
        XCTAssertEqual(root.fileCount, 2)
    }

    func testManySmallFilesAreRolledUp() throws {
        for i in 0..<120 { try write("many/f\(i).txt", bytes: 100) }
        let root = try XCTUnwrap(DiskScanner().scan(path: dir.path))
        let many = root.children[0]
        XCTAssertEqual(many.fileCount, 120)
        XCTAssertEqual(many.children.count, DiskScanner.smallKeepPerDir)
        XCTAssertEqual(many.smallCount, 120 - DiskScanner.smallKeepPerDir)
        XCTAssertEqual(many.size, many.children.map(\.size).reduce(0, +) + many.smallSize)
    }

    func testDetachUpdatesAncestors() throws {
        try write("keep.bin", bytes: 1_200_000)
        try write("sub/drop.bin", bytes: 2_400_000)
        let root = try XCTUnwrap(DiskScanner().scan(path: dir.path))
        let sub = try XCTUnwrap(root.children.first { $0.name == "sub" })
        sub.detach()
        XCTAssertEqual(root.size, allocated("keep.bin"))
        XCTAssertEqual(root.fileCount, 1)
        XCTAssertEqual(root.children.count, 1)
    }

    func testMissingPathReturnsNil() {
        XCTAssertNil(DiskScanner().scan(path: dir.path + "/nope"))
    }
}
