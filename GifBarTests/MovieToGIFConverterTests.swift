//
//  MovieToGIFConverterTests.swift
//  GifBarTests
//
//  Integration tests for the .mov → .gif pipeline. A synthetic movie is built
//  with MovieWriter, then converted — no real screen capture needed (SPEC §4.5).
//

import XCTest
import AVFoundation
import CoreVideo
import ImageIO
@testable import GifBar

final class MovieToGIFConverterTests: XCTestCase {

    private var movieURL: URL!
    private var gifURL: URL?

    override func setUp() {
        super.setUp()
        movieURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gifbar-conv-src-\(UUID().uuidString).mov")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: movieURL)
        if let gifURL { try? FileManager.default.removeItem(at: gifURL) }
        movieURL = nil
        gifURL = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// A solid-grey BGRA pixel buffer; varying `fill` per frame keeps the H.264
    /// encoder from collapsing identical frames.
    private func makePixelBuffer(width: Int, height: Int, fill: UInt8) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, nil, &buffer
        )
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, Int32(fill), CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    /// Writes a deterministic synthetic movie of `frameCount` frames at `fps`.
    private func writeMovie(frameCount: Int, width: Int, height: Int, fps: Int) async throws {
        let writer = try MovieWriter(
            outputURL: movieURL, pixelWidth: width, pixelHeight: height,
            frameRate: fps, realtime: false
        )
        for index in 0..<frameCount {
            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            var attempts = 0
            while !writer.isReady && index > 0 && attempts < 1000 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.002))
                attempts += 1
            }
            _ = writer.append(makePixelBuffer(width: width, height: height,
                                              fill: UInt8(40 + index * 5)), at: time)
        }
        await writer.finish()
    }

    /// Reads the produced GIF's frame count and first-frame dimensions.
    private func inspectGIF(_ url: URL) -> (frames: Int, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (CGImageSourceGetCount(source), first.width, first.height)
    }

    private func loopCount(of url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return nil }
        return gif[kCGImagePropertyGIFLoopCount] as? Int
    }

    // MARK: - Tests

    func testProducesValidLoopingGIF() async throws {
        try await writeMovie(frameCount: 12, width: 160, height: 120, fps: 12)

        let url = try await MovieToGIFConverter().convert(movieURL: movieURL, fps: .fps10)
        gifURL = url

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let info = inspectGIF(url)
        XCTAssertNotNil(info)
        XCTAssertGreaterThan(info?.frames ?? 0, 0)
        XCTAssertEqual(loopCount(of: url), 0)
    }

    func testGIFMatchesSourceDimensions() async throws {
        try await writeMovie(frameCount: 8, width: 160, height: 120, fps: 15)

        let url = try await MovieToGIFConverter().convert(movieURL: movieURL, fps: .fps15)
        gifURL = url

        let info = inspectGIF(url)
        XCTAssertEqual(info?.width, 160)
        XCTAssertEqual(info?.height, 120)
    }

    func testDropsFramesWhenTargetFpsIsLower() async throws {
        // 1 second of footage at 24 fps...
        try await writeMovie(frameCount: 24, width: 160, height: 120, fps: 24)

        // ...converted to 10 fps should yield roughly 10 frames, never 24.
        let url = try await MovieToGIFConverter().convert(movieURL: movieURL, fps: .fps10)
        gifURL = url

        let frames = inspectGIF(url)?.frames ?? 0
        XCTAssertLessThan(frames, 24, "lower target fps must drop frames")
        XCTAssertGreaterThanOrEqual(frames, 7)
        XCTAssertLessThanOrEqual(frames, 13)
    }

    func testThrowsOnMissingVideoTrack() async throws {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("gifbar-missing-\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }

        do {
            _ = try await MovieToGIFConverter().convert(movieURL: bogus, fps: .fps15)
            XCTFail("expected conversion to throw on a non-movie file")
        } catch {
            // Expected — any error type is acceptable here.
        }
    }
}
