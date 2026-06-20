//
//  OutputHandlerTests.swift
//  GifBarTests
//
//  Unit tests for OutputHandler's file placement logic. Uses ordinary temp
//  directories (inside the app container) so no security-scoped access or
//  powerbox is involved (SPEC §4.6).
//

import XCTest
@testable import GifBar

final class OutputHandlerTests: XCTestCase {

    private var workDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gifbar-output-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
        workDir = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Writes a tiny stand-in GIF file and returns its URL.
    private func makeSourceGIF() throws -> URL {
        let url = workDir.appendingPathComponent("src-\(UUID().uuidString).gif")
        try Data("GIF89a".utf8).write(to: url)
        return url
    }

    private func fixedDate() -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 17
        components.hour = 14; components.minute = 32; components.second = 45
        return Calendar.current.date(from: components)!
    }

    // MARK: - Tests

    func testSaveMovesFileIntoFolder() throws {
        let source = try makeSourceGIF()
        let folder = workDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let result = try OutputHandler().save(gifAt: source, toFolder: folder)

        XCTAssertEqual(result.deletingLastPathComponent().path, folder.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path),
                       "the temp source should be moved, not copied")
    }

    func testSaveCreatesMissingFolder() throws {
        let source = try makeSourceGIF()
        let folder = workDir.appendingPathComponent("does/not/exist/yet")

        let result = try OutputHandler().save(gifAt: source, toFolder: folder)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }

    func testFileNameIsTimestamped() {
        let name = OutputHandler.fileName(for: fixedDate())
        // Don't assert the exact time (timezone-dependent); assert the shape.
        let pattern = #"^GifBar \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}\.gif$"#
        XCTAssertNotNil(name.range(of: pattern, options: .regularExpression),
                        "unexpected name: \(name)")
    }

    func testSaveAvoidsNameCollision() throws {
        let folder = workDir.appendingPathComponent("dest")
        let date = fixedDate()

        // Two saves forced to the same timestamp must not overwrite each other.
        let first = try OutputHandler().save(gifAt: try makeSourceGIF(), toFolder: folder, date: date)
        let second = try OutputHandler().save(gifAt: try makeSourceGIF(), toFolder: folder, date: date)

        XCTAssertNotEqual(first.path, second.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(second.lastPathComponent.contains("(2)"),
                      "collision suffix expected, got \(second.lastPathComponent)")
    }
}
