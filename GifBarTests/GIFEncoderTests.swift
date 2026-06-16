//
//  GIFEncoderTests.swift
//  GifBarTests
//
//  Unit tests for GIFEncoder using synthetic CGImages — no movie, capture, or
//  permission needed (SPEC §4.5).
//

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import GifBar

final class GIFEncoderTests: XCTestCase {

    private var outputURL: URL!

    override func setUp() {
        super.setUp()
        outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gifbar-encoder-test-\(UUID().uuidString).gif")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outputURL)
        outputURL = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a solid-colour RGBA image of the given size.
    private func makeImage(width: Int, height: Int, gray: UInt8 = 128) -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: gray, count: bytesPerRow * height)
        let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    /// Reads back the GIF's frame count and dimensions.
    private func inspect(_ url: URL) -> (frames: Int, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let frames = CGImageSourceGetCount(source)
        guard let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (frames, first.width, first.height)
    }

    /// Reads the per-frame GIF delay (in seconds) at the given index.
    private func delay(of url: URL, at index: Int) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any],
              let value = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double else {
            return nil
        }
        return value
    }

    /// Reads the file-level loop count.
    private func loopCount(of url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return nil
        }
        return gif[kCGImagePropertyGIFLoopCount] as? Int
    }

    // MARK: - Tests

    func testWritesExpectedFrameCount() throws {
        var encoder = try GIFEncoder(outputURL: outputURL, capacity: 3)
        for _ in 0..<3 {
            encoder.append(makeImage(width: 40, height: 30), delaySeconds: 0.1)
        }
        XCTAssertTrue(encoder.finalize())

        let info = inspect(outputURL)
        XCTAssertEqual(info?.frames, 3)
        XCTAssertEqual(info?.width, 40)
        XCTAssertEqual(info?.height, 30)
    }

    func testLoopsForever() throws {
        var encoder = try GIFEncoder(outputURL: outputURL)
        encoder.append(makeImage(width: 10, height: 10), delaySeconds: 0.1)
        XCTAssertTrue(encoder.finalize())

        // A loop count of 0 means "loop indefinitely".
        XCTAssertEqual(loopCount(of: outputURL), 0)
    }

    func testStoresRequestedDelay() throws {
        var encoder = try GIFEncoder(outputURL: outputURL)
        encoder.append(makeImage(width: 10, height: 10), delaySeconds: 0.1)
        XCTAssertTrue(encoder.finalize())

        // 15 fps would be ~0.0667; here we asked for 0.1 (10 fps) exactly.
        let d = try XCTUnwrap(delay(of: outputURL, at: 0))
        XCTAssertEqual(d, 0.1, accuracy: 0.005)
    }

    func testRoundsDelayToCentisecond() throws {
        var encoder = try GIFEncoder(outputURL: outputURL)
        // 1/15 s = 0.0666… should round to 0.07 (centisecond resolution).
        encoder.append(makeImage(width: 10, height: 10), delaySeconds: 1.0 / 15.0)
        XCTAssertTrue(encoder.finalize())

        let d = try XCTUnwrap(delay(of: outputURL, at: 0))
        XCTAssertEqual(d, 0.07, accuracy: 0.0001)
    }

    func testFinalizeWithoutFramesLeavesNoFile() throws {
        let encoder = try GIFEncoder(outputURL: outputURL)
        XCTAssertFalse(encoder.finalize())
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }
}
