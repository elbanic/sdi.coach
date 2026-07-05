// TerminalRendererTests.swift
// TDD RED Phase: Failing tests for TerminalRenderer
//
// Tasks covered:
// - 5.2.1: Terminal width detection
// - 5.2.2: Unicode-aware text wrapping
// - 5.2.4: Fixed-position status bar
//
// Test framework: swift-testing (NOT XCTest)

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 5.2.1: Terminal Width Detection Tests

@Suite("Terminal Width Detection")
struct TerminalWidthDetectionTests {

    @Test("TerminalRenderer should have terminalWidth property")
    func testTerminalWidthPropertyExists() {
        let renderer = TerminalRenderer()
        let width = renderer.terminalWidth
        // Should return a positive integer representing terminal columns
        #expect(width > 0)
    }

    @Test("Terminal width should have a reasonable default when not in a terminal")
    func testDefaultTerminalWidth() {
        let renderer = TerminalRenderer()
        // Default width should be 80 columns when not attached to a terminal
        #expect(renderer.terminalWidth >= 40)
        #expect(renderer.terminalWidth <= 500)
    }

    @Test("TerminalRenderer should detect width from environment")
    func testDetectWidthFromEnvironment() {
        // Create renderer with mock terminal provider
        let mockProvider = MockTerminalProvider(width: 120, height: 40)
        let renderer = TerminalRenderer(terminalProvider: mockProvider)

        #expect(renderer.terminalWidth == 120)
    }

    @Test("TerminalRenderer should update width when terminal is resized")
    func testWidthUpdatesOnResize() async {
        let mockProvider = MockTerminalProvider(width: 80, height: 24)
        let renderer = TerminalRenderer(terminalProvider: mockProvider)

        // Initial width
        #expect(renderer.terminalWidth == 80)

        // Simulate terminal resize
        mockProvider.simulateResize(width: 120, height: 40)

        // Width should update
        #expect(renderer.terminalWidth == 120)
    }

    @Test("TerminalRenderer should have terminalHeight property")
    func testTerminalHeightPropertyExists() {
        let renderer = TerminalRenderer()
        let height = renderer.terminalHeight
        #expect(height > 0)
    }

    @Test("TerminalRenderer should handle very narrow terminals")
    func testNarrowTerminal() {
        let mockProvider = MockTerminalProvider(width: 20, height: 10)
        let renderer = TerminalRenderer(terminalProvider: mockProvider)

        #expect(renderer.terminalWidth == 20)
    }

    @Test("TerminalRenderer should handle very wide terminals")
    func testWideTerminal() {
        let mockProvider = MockTerminalProvider(width: 300, height: 50)
        let renderer = TerminalRenderer(terminalProvider: mockProvider)

        #expect(renderer.terminalWidth == 300)
    }
}

// MARK: - Task 5.2.2: Unicode-Aware Text Wrapping Tests

@Suite("Unicode-Aware Text Wrapping")
struct TextWrappingTests {

    // MARK: - Basic Text Wrapping

    @Test("wrapText should return single line for short text")
    func testShortTextNoWrap() {
        let renderer = TerminalRenderer()
        let lines = renderer.wrapText("Hello", maxWidth: 80)

        #expect(lines.count == 1)
        #expect(lines.first == "Hello")
    }

    @Test("wrapText should wrap long text into multiple lines")
    func testLongTextWraps() {
        let renderer = TerminalRenderer()
        let text = "This is a very long sentence that should be wrapped across multiple lines when the width is narrow"
        let lines = renderer.wrapText(text, maxWidth: 30)

        #expect(lines.count > 1)
        // Each line should not exceed maxWidth
        for line in lines {
            #expect(line.count <= 30)
        }
    }

    @Test("wrapText should preserve words when possible")
    func testWrapPreservesWords() {
        let renderer = TerminalRenderer()
        let text = "Hello World Test"
        let lines = renderer.wrapText(text, maxWidth: 10)

        // Words should not be split if possible
        // "Hello" = 5 chars, "World" = 5 chars, "Test" = 4 chars
        // With maxWidth 10, "Hello" fits alone
        #expect(lines.first == "Hello")
    }

    @Test("wrapText should break long words that exceed maxWidth")
    func testBreakLongWords() {
        let renderer = TerminalRenderer()
        let text = "Supercalifragilisticexpialidocious"
        let lines = renderer.wrapText(text, maxWidth: 10)

        // Word must be broken since it exceeds maxWidth
        #expect(lines.count > 1)
        for line in lines {
            #expect(line.count <= 10)
        }
    }

    @Test("wrapText should handle empty string")
    func testEmptyString() {
        let renderer = TerminalRenderer()
        let lines = renderer.wrapText("", maxWidth: 80)

        #expect(lines.isEmpty || lines == [""])
    }

    @Test("wrapText should handle whitespace-only string")
    func testWhitespaceOnlyString() {
        let renderer = TerminalRenderer()
        let lines = renderer.wrapText("   ", maxWidth: 80)

        // Should handle gracefully (either empty or trimmed)
        #expect(lines.count <= 1)
    }

    // MARK: - Unicode / CJK Character Handling

    @Test("wrapText should handle Korean characters correctly")
    func testKoreanCharacters() {
        let renderer = TerminalRenderer()
        // Korean characters are typically 2 columns wide (fullwidth)
        let text = "안녕하세요 반갑습니다"  // "Hello, nice to meet you"
        let lines = renderer.wrapText(text, maxWidth: 20)

        // Should wrap considering double-width characters
        #expect(lines.count >= 1)
        for line in lines {
            let displayWidth = renderer.displayWidth(of: line)
            #expect(displayWidth <= 20)
        }
    }

    @Test("wrapText should handle Chinese characters correctly")
    func testChineseCharacters() {
        let renderer = TerminalRenderer()
        let text = "你好世界这是一个测试"  // "Hello world this is a test"
        let lines = renderer.wrapText(text, maxWidth: 16)

        for line in lines {
            let displayWidth = renderer.displayWidth(of: line)
            #expect(displayWidth <= 16)
        }
    }

    @Test("wrapText should handle Japanese characters correctly")
    func testJapaneseCharacters() {
        let renderer = TerminalRenderer()
        let text = "こんにちは世界"  // "Hello world"
        let lines = renderer.wrapText(text, maxWidth: 12)

        for line in lines {
            let displayWidth = renderer.displayWidth(of: line)
            #expect(displayWidth <= 12)
        }
    }

    @Test("wrapText should handle emoji correctly")
    func testEmojiCharacters() {
        let renderer = TerminalRenderer()
        // Emoji are typically 2 columns wide
        let text = "Hello World!"
        let lines = renderer.wrapText(text, maxWidth: 20)

        for line in lines {
            let displayWidth = renderer.displayWidth(of: line)
            #expect(displayWidth <= 20)
        }
    }

    @Test("wrapText should handle mixed ASCII and CJK")
    func testMixedASCIIAndCJK() {
        let renderer = TerminalRenderer()
        let text = "Hello 안녕 World 세계"
        let lines = renderer.wrapText(text, maxWidth: 20)

        for line in lines {
            let displayWidth = renderer.displayWidth(of: line)
            #expect(displayWidth <= 20)
        }
    }

    @Test("wrapText should handle combining characters")
    func testCombiningCharacters() {
        let renderer = TerminalRenderer()
        // e + combining acute accent = 1 display width
        let text = "cafe\u{0301}"  // "cafe" with combining accent on e
        let lines = renderer.wrapText(text, maxWidth: 80)

        #expect(lines.count == 1)
        // Display width should be 5 (c-a-f-e-accent counts as one grapheme)
        let displayWidth = renderer.displayWidth(of: text)
        #expect(displayWidth == 5)
    }

    @Test("wrapText should handle zero-width characters")
    func testZeroWidthCharacters() {
        let renderer = TerminalRenderer()
        // Zero-width joiner
        let text = "Hello\u{200B}World"  // zero-width space
        let displayWidth = renderer.displayWidth(of: text)

        // Zero-width space should not add to display width
        #expect(displayWidth == 10)  // "HelloWorld" = 10
    }

    // MARK: - Display Width Calculation

    @Test("displayWidth should return correct width for ASCII")
    func testDisplayWidthASCII() {
        let renderer = TerminalRenderer()
        #expect(renderer.displayWidth(of: "Hello") == 5)
        #expect(renderer.displayWidth(of: "a") == 1)
        #expect(renderer.displayWidth(of: "") == 0)
    }

    @Test("displayWidth should return double width for CJK characters")
    func testDisplayWidthCJK() {
        let renderer = TerminalRenderer()
        // Each CJK character should be 2 columns
        #expect(renderer.displayWidth(of: "가") == 2)  // Korean
        #expect(renderer.displayWidth(of: "你") == 2)  // Chinese
        #expect(renderer.displayWidth(of: "あ") == 2)  // Japanese Hiragana
    }

    @Test("displayWidth should return double width for emoji")
    func testDisplayWidthEmoji() {
        let renderer = TerminalRenderer()
        // Emoji are typically 2 columns wide
        #expect(renderer.displayWidth(of: "😀") == 2)
        #expect(renderer.displayWidth(of: "🎉") == 2)
    }

    // MARK: - Edge Cases

    @Test("wrapText should handle newlines in input")
    func testNewlinesInInput() {
        let renderer = TerminalRenderer()
        let text = "Line one\nLine two"
        let lines = renderer.wrapText(text, maxWidth: 80)

        // Should preserve or handle newlines appropriately
        #expect(lines.count >= 2)
    }

    @Test("wrapText should handle tabs in input")
    func testTabsInInput() {
        let renderer = TerminalRenderer()
        let text = "Hello\tWorld"
        let lines = renderer.wrapText(text, maxWidth: 80)

        // Tabs should be converted to spaces or handled appropriately
        #expect(lines.count >= 1)
    }

    @Test("wrapText should handle maxWidth of 1")
    func testMinimalWidth() {
        let renderer = TerminalRenderer()
        let text = "Hi"
        let lines = renderer.wrapText(text, maxWidth: 1)

        // Each character on its own line
        #expect(lines.count == 2)
        #expect(lines[0] == "H")
        #expect(lines[1] == "i")
    }

    @Test("wrapText should handle very long text efficiently")
    func testVeryLongText() {
        let renderer = TerminalRenderer()
        let text = String(repeating: "word ", count: 1000)
        let lines = renderer.wrapText(text, maxWidth: 80)

        // Should complete without performance issues
        #expect(lines.count > 0)
        for line in lines {
            #expect(line.count <= 80)
        }
    }

    @Test("wrapText should trim trailing whitespace from lines")
    func testTrimTrailingWhitespace() {
        let renderer = TerminalRenderer()
        let text = "Hello    World"
        let lines = renderer.wrapText(text, maxWidth: 10)

        for line in lines {
            #expect(!line.hasSuffix(" "))
        }
    }

    @Test("wrapText should handle multiple consecutive spaces")
    func testMultipleConsecutiveSpaces() {
        let renderer = TerminalRenderer()
        let text = "Hello     World"
        let lines = renderer.wrapText(text, maxWidth: 80)

        // Multiple spaces should be preserved or collapsed appropriately
        #expect(lines.count >= 1)
    }
}

// MARK: - Task 5.2.4: Status Bar Rendering Tests

@Suite("Status Bar Rendering")
struct StatusBarRenderingTests {

    @Test("renderStatusBar should return formatted string")
    func testStatusBarReturnsString() {
        let renderer = TerminalRenderer()
        let statusBar = renderer.renderStatusBar(
            mode: .idle,
            micOn: false,
            remainingTime: "30:00"
        )

        #expect(!statusBar.isEmpty)
    }

    @Test("renderStatusBar should include mode indicator")
    func testStatusBarIncludesMode() {
        let renderer = TerminalRenderer()

        let idleBar = renderer.renderStatusBar(mode: .idle, micOn: false, remainingTime: "30:00")
        let interviewingBar = renderer.renderStatusBar(mode: .interviewing, micOn: true, remainingTime: "25:00")
        let pausedBar = renderer.renderStatusBar(mode: .paused, micOn: false, remainingTime: "20:00")
        let feedbackBar = renderer.renderStatusBar(mode: .feedback, micOn: false, remainingTime: "00:00")

        // Each mode should have a distinct representation
        #expect(idleBar.contains("Idle") || idleBar.contains("idle") || idleBar.contains("Ready"))
        #expect(interviewingBar.contains("Interview") || interviewingBar.contains("interview"))
        #expect(pausedBar.contains("Pause") || pausedBar.contains("pause"))
        #expect(feedbackBar.contains("Feedback") || feedbackBar.contains("feedback"))
    }

    @Test("renderStatusBar should include mic status indicator")
    func testStatusBarIncludesMicStatus() {
        let renderer = TerminalRenderer()

        let micOnBar = renderer.renderStatusBar(mode: .interviewing, micOn: true, remainingTime: "25:00")
        let micOffBar = renderer.renderStatusBar(mode: .interviewing, micOn: false, remainingTime: "25:00")

        // Mic on/off should have different representations
        #expect(micOnBar != micOffBar)
        // Common representations: "MIC ON", "ON", mic emoji, etc.
        #expect(micOnBar.contains("ON") || micOnBar.contains("on") || micOnBar.contains("MIC"))
    }

    @Test("renderStatusBar should include remaining time")
    func testStatusBarIncludesRemainingTime() {
        let renderer = TerminalRenderer()

        let statusBar = renderer.renderStatusBar(
            mode: .interviewing,
            micOn: true,
            remainingTime: "24:35"
        )

        #expect(statusBar.contains("24:35"))
    }

    @Test("renderStatusBar should respect terminal width")
    func testStatusBarRespectsTerminalWidth() {
        let mockProvider = MockTerminalProvider(width: 60, height: 24)
        let renderer = TerminalRenderer(terminalProvider: mockProvider)

        let statusBar = renderer.renderStatusBar(
            mode: .interviewing,
            micOn: true,
            remainingTime: "25:00"
        )

        let displayWidth = renderer.displayWidth(of: statusBar)
        #expect(displayWidth <= 60)
    }

    @Test("renderStatusBar should include available commands hint")
    func testStatusBarIncludesCommandsHint() {
        let renderer = TerminalRenderer()

        let idleBar = renderer.renderStatusBar(mode: .idle, micOn: false, remainingTime: "30:00")
        let interviewingBar = renderer.renderStatusBar(mode: .interviewing, micOn: true, remainingTime: "25:00")

        // Idle mode should hint at /start
        #expect(idleBar.contains("/start") || idleBar.contains("start"))

        // Interviewing mode should hint at /pause and /end
        #expect(interviewingBar.contains("/pause") || interviewingBar.contains("/end") ||
                interviewingBar.contains("pause") || interviewingBar.contains("end"))
    }

    @Test("renderStatusBar should use ANSI escape codes for colors")
    func testStatusBarUsesANSIColors() {
        let renderer = TerminalRenderer()
        let statusBar = renderer.renderStatusBar(
            mode: .interviewing,
            micOn: true,
            remainingTime: "25:00"
        )

        // ANSI escape codes start with \u{1B}[ or \033[
        #expect(statusBar.contains("\u{1B}[") || statusBar.contains("\u{001B}["))
    }

    @Test("renderStatusBar should have plain text option")
    func testStatusBarPlainText() {
        let renderer = TerminalRenderer()
        let statusBar = renderer.renderStatusBar(
            mode: .interviewing,
            micOn: true,
            remainingTime: "25:00",
            useColors: false
        )

        // Should not contain ANSI escape codes
        #expect(!statusBar.contains("\u{1B}["))
        #expect(!statusBar.contains("\u{001B}["))
    }

    @Test("renderStatusBar should handle all ApplicationMode cases")
    func testStatusBarHandlesAllModes() {
        let renderer = TerminalRenderer()

        // Should not crash for any mode
        let modes: [ApplicationMode] = [.idle, .interviewing, .paused, .feedback]
        for mode in modes {
            let statusBar = renderer.renderStatusBar(
                mode: mode,
                micOn: false,
                remainingTime: "00:00"
            )
            #expect(!statusBar.isEmpty)
        }
    }

    @Test("renderStatusBar with narrow terminal should still be readable")
    func testStatusBarNarrowTerminal() {
        let mockProvider = MockTerminalProvider(width: 40, height: 24)
        let renderer = TerminalRenderer(terminalProvider: mockProvider)

        let statusBar = renderer.renderStatusBar(
            mode: .interviewing,
            micOn: true,
            remainingTime: "25:00"
        )

        // Should still contain essential information
        #expect(statusBar.contains("25:00"))
        let displayWidth = renderer.displayWidth(of: statusBar)
        #expect(displayWidth <= 40)
    }
}

// MARK: - TerminalRenderer ANSI Control Tests

@Suite("ANSI Terminal Control")
struct ANSITerminalControlTests {

    @Test("clearLine should return ANSI clear line sequence")
    func testClearLine() {
        let renderer = TerminalRenderer()
        let clearSequence = renderer.clearLine()

        // Standard ANSI clear line: \033[2K
        #expect(clearSequence.contains("\u{1B}[") || clearSequence.contains("\u{001B}["))
    }

    @Test("moveCursor should return ANSI cursor movement sequence")
    func testMoveCursor() {
        let renderer = TerminalRenderer()
        let moveSequence = renderer.moveCursor(row: 5, column: 10)

        // Standard ANSI cursor position: \033[5;10H
        #expect(moveSequence.contains("\u{1B}[") || moveSequence.contains("\u{001B}["))
        #expect(moveSequence.contains("5") && moveSequence.contains("10"))
    }

    @Test("saveCursor should return ANSI save cursor sequence")
    func testSaveCursor() {
        let renderer = TerminalRenderer()
        let saveSequence = renderer.saveCursor()

        // Standard ANSI save cursor: \033[s or \0337
        #expect(saveSequence.contains("\u{1B}") || saveSequence.contains("\u{001B}"))
    }

    @Test("restoreCursor should return ANSI restore cursor sequence")
    func testRestoreCursor() {
        let renderer = TerminalRenderer()
        let restoreSequence = renderer.restoreCursor()

        // Standard ANSI restore cursor: \033[u or \0338
        #expect(restoreSequence.contains("\u{1B}") || restoreSequence.contains("\u{001B}"))
    }

    @Test("setColor should return ANSI color sequence")
    func testSetColor() {
        let renderer = TerminalRenderer()

        let redSequence = renderer.setColor(.red)
        let greenSequence = renderer.setColor(.green)
        let resetSequence = renderer.resetColor()

        #expect(redSequence.contains("\u{1B}["))
        #expect(greenSequence.contains("\u{1B}["))
        #expect(resetSequence.contains("\u{1B}["))

        // Different colors should produce different sequences
        #expect(redSequence != greenSequence)
    }

    @Test("setBold should return ANSI bold sequence")
    func testSetBold() {
        let renderer = TerminalRenderer()
        let boldSequence = renderer.setBold()

        // Standard ANSI bold: \033[1m
        #expect(boldSequence.contains("\u{1B}[1m") || boldSequence.contains("\u{001B}[1m"))
    }
}

// MARK: - TerminalRenderer Thread Safety Tests

@Suite("TerminalRenderer Thread Safety")
struct TerminalRendererThreadSafetyTests {

    @Test("TerminalRenderer should be thread-safe for concurrent access")
    func testConcurrentAccess() async {
        let renderer = TerminalRenderer()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    _ = renderer.terminalWidth
                    _ = renderer.wrapText("Test text \(i)", maxWidth: 80)
                    _ = renderer.renderStatusBar(
                        mode: .interviewing,
                        micOn: i % 2 == 0,
                        remainingTime: "25:00"
                    )
                }
            }
        }

        // Should complete without crash
        #expect(renderer.terminalWidth > 0)
    }
}

// MARK: - Mock Types for Tests

/// Mock terminal provider for testing
final class MockTerminalProvider: TerminalProviding, @unchecked Sendable {
    private var _width: Int
    private var _height: Int
    private let lock = NSLock()

    var width: Int {
        lock.lock()
        defer { lock.unlock() }
        return _width
    }

    var height: Int {
        lock.lock()
        defer { lock.unlock() }
        return _height
    }

    init(width: Int, height: Int) {
        self._width = width
        self._height = height
    }

    func simulateResize(width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }
        self._width = width
        self._height = height
    }

    public func getTerminalSize() -> (width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (_width, _height)
    }
}
