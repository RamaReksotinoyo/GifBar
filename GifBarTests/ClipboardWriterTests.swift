//
//  ClipboardWriterTests.swift
//  GifBarTests
//
//  Unit tests for copying a GIF to the pasteboard (Iteration 7b, SPEC §4.6).
//  Uses a private, uniquely-named NSPasteboard so the real system clipboard is
//  never touched.
//

import XCTest
import AppKit
@testable import GifBar

@MainActor
final class ClipboardWriterTests: XCTestCase {

    private var pasteboard: NSPasteboard!
    private var gifURL: URL!
    private let gifBytes = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) // "GIF89a"

    override func setUpWithError() throws {
        try super.setUpWithError()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("gifbar-clip-test-\(UUID().uuidString)"))
        gifURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-\(UUID().uuidString).gif")
        try gifBytes.write(to: gifURL)
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        try? FileManager.default.removeItem(at: gifURL)
        gifURL = nil
        super.tearDown()
    }

    func testWriteGIFSucceeds() {
        XCTAssertTrue(ClipboardWriter(pasteboard: pasteboard).writeGIF(at: gifURL))
    }

    func testWriteGIFPutsRawGIFData() {
        ClipboardWriter(pasteboard: pasteboard).writeGIF(at: gifURL)
        let data = pasteboard.data(forType: ClipboardWriter.gifType)
        XCTAssertEqual(data, gifBytes)
    }

    func testWriteGIFPutsFileURL() {
        ClipboardWriter(pasteboard: pasteboard).writeGIF(at: gifURL)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(urls?.first, gifURL)
    }

    func testWriteGIFFromDataPutsBothRepresentations() {
        // The data variant is what the store uses: bytes already in hand plus a
        // file URL that may point to a security-scoped (unreadable) location.
        let fileURL = URL(fileURLWithPath: "/somewhere/GifBar.gif")
        XCTAssertTrue(
            ClipboardWriter(pasteboard: pasteboard).writeGIF(data: gifBytes, fileURL: fileURL)
        )
        XCTAssertEqual(pasteboard.data(forType: ClipboardWriter.gifType), gifBytes)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(urls?.first, fileURL)
    }

    func testWriteGIFFailsForMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).gif")
        XCTAssertFalse(ClipboardWriter(pasteboard: pasteboard).writeGIF(at: missing))
    }
}
