//
//  HotKeyCenterTests.swift
//  GifBarTests
//
//  Unit tests for the global-hotkey key mapping (Iteration 7c, SPEC §6).
//  Registration itself needs a live Carbon run loop, so only the pure key/
//  modifier constants are checked here; the rest is verified at runtime.
//

import XCTest
import Carbon
@testable import GifBar

@MainActor
final class HotKeyCenterTests: XCTestCase {

    func testKeyCodeIsDigit5() {
        XCTAssertEqual(HotKeyCenter.keyCode, UInt32(kVK_ANSI_5))
        XCTAssertEqual(HotKeyCenter.keyCode, 23)
    }

    func testModifiersAreCommandShift() {
        XCTAssertEqual(HotKeyCenter.modifiers, UInt32(cmdKey | shiftKey))
    }
}
