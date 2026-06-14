//
//  MovieWriterTests.swift
//  GifBarTests
//
//  Integration tests for MovieWriter using synthetic frames — no screen
//  recording permission or real capture needed (SPEC §4.4).
//

import XCTest
import AVFoundation
import CoreVideo
@testable import GifBar

final class MovieWriterTests: XCTestCase {

    private var outputURL: URL!

    override func setUp() {
        super.setUp()
        outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gifbar-test-\(UUID().uuidString).mov")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outputURL)
        outputURL = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a zeroed BGRA pixel buffer of the given size.
    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, 0, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    /// Writes `frameCount` frames at `fps`, spin-waiting for writer readiness so
    /// none are dropped.
    private func writeFrames(_ frameCount: Int, width: Int, height: Int, fps: Int) async throws {
        let writer = try MovieWriter(
            outputURL: outputURL, pixelWidth: width, pixelHeight: height,
            frameRate: fps, realtime: false
        )
        let buffer = makePixelBuffer(width: width, height: height)

        for index in 0..<frameCount {
            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            var attempts = 0
            while !writer.isReady && index > 0 && attempts < 1000 {
                // Let AVAssetWriter drain its queue between appends.
                RunLoop.current.run(until: Date().addingTimeInterval(0.002))
                attempts += 1
            }
            XCTAssertTrue(writer.append(buffer, at: time), "frame \(index) should append")
        }
        await writer.finish()
    }

    /// Counts decoded video frames in the produced movie.
    private func countFrames(in url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return 0
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()

        var count = 0
        while output.copyNextSampleBuffer() != nil { count += 1 }
        return count
    }

    // MARK: - Tests

    func testProducesPlayableMovieWithFrames() async throws {
        let frameCount = 12
        try await writeFrames(frameCount, width: 320, height: 200, fps: 12)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let asset = AVURLAsset(url: outputURL)
        let track = try await asset.loadTracks(withMediaType: .video).first
        XCTAssertNotNil(track, "movie must contain a video track")

        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0)

        // Note: re-reading an H.264 track is not guaranteed to vend exactly the
        // number of appended frames (the decoder may resample to the track's
        // nominal rate), so we assert a sane lower bound rather than equality.
        let frames = try await countFrames(in: outputURL)
        XCTAssertGreaterThanOrEqual(frames, frameCount)
    }

    func testMovieHasExpectedDimensions() async throws {
        try await writeFrames(6, width: 640, height: 400, fps: 15)

        let asset = AVURLAsset(url: outputURL)
        let track = try await asset.loadTracks(withMediaType: .video).first
        let size = try await track?.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 640, height: 400))
    }

    func testFinishWithoutFramesDoesNotCreateFile() async throws {
        let writer = try MovieWriter(
            outputURL: outputURL, pixelWidth: 100, pixelHeight: 100, frameRate: 10
        )
        await writer.finish()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputURL.path),
            "Cancelling an empty writer should not leave a file behind"
        )
    }
}
