// HeaderViewTests.swift
// TDD RED Phase: Failing tests for HeaderView
//
// Task 5.3.2: HeaderView - Logo display, version display, timer display
//
// Test framework: swift-testing (NOT XCTest)
// Feature: sdi.coach TUI Components

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 5.3.2: HeaderView Tests

@Suite("HeaderView Initialization")
struct HeaderViewInitializationTests {

    @Test("HeaderView should be initializable")
    func testHeaderViewInitializable() {
        let view = HeaderView()
        #expect(view != nil)
    }

    @Test("HeaderView should accept terminal width")
    func testHeaderViewWithTerminalWidth() {
        let view = HeaderView(terminalWidth: 80)
        #expect(view.terminalWidth == 80)
    }

    @Test("HeaderView should have default terminal width")
    func testDefaultTerminalWidth() {
        let view = HeaderView()
        #expect(view.terminalWidth > 0)
        #expect(view.terminalWidth >= 40) // Minimum reasonable width
    }
}

@Suite("HeaderView Logo Display")
struct HeaderViewLogoDisplayTests {

    @Test("HeaderView should render logo")
    func testRenderLogo() {
        let view = HeaderView(terminalWidth: 80)
        let output = view.render()

        // Should contain ASCII art logo elements
        #expect(output.contains("sdi.coach") || output.contains("SDI"))
    }

    @Test("HeaderView logo should be ASCII art")
    func testLogoIsASCIIArt() {
        let view = HeaderView(terminalWidth: 80)
        let output = view.render()

        // ASCII art typically uses these characters
        let hasArtElements = output.contains("#") ||
                             output.contains("@") ||
                             output.contains("=") ||
                             output.contains("-") ||
                             output.contains("_") ||
                             output.contains("|") ||
                             output.contains("/") ||
                             output.contains("\\")
        #expect(hasArtElements)
    }

    @Test("HeaderView logo should fit terminal width")
    func testLogoFitsTerminalWidth() {
        let view = HeaderView(terminalWidth: 60)
        let output = view.render()
        let lines = output.split(separator: "\n")

        for line in lines {
            // Check visible width (excluding ANSI escape codes)
            let strippedLine = stripANSI(String(line))
            #expect(strippedLine.count <= 60)
        }
    }

    @Test("HeaderView should have compact logo for narrow terminals")
    func testCompactLogoForNarrowTerminal() {
        let wideView = HeaderView(terminalWidth: 100)
        let narrowView = HeaderView(terminalWidth: 40)

        let wideOutput = wideView.render()
        let narrowOutput = narrowView.render()

        // Narrow terminal should have shorter lines
        let wideLines = wideOutput.split(separator: "\n")
        let narrowLines = narrowOutput.split(separator: "\n")

        let maxWideWidth = wideLines.map { stripANSI(String($0)).count }.max() ?? 0
        let maxNarrowWidth = narrowLines.map { stripANSI(String($0)).count }.max() ?? 0

        #expect(maxNarrowWidth <= maxWideWidth)
    }
}

@Suite("HeaderView Version Display")
struct HeaderViewVersionDisplayTests {

    @Test("HeaderView should display version")
    func testDisplayVersion() {
        let view = HeaderView(terminalWidth: 80)
        let output = view.render()

        // Should contain version number in format like "v0.1.0" or "0.1.0"
        let containsVersion = output.contains("v") && output.contains(".")
        #expect(containsVersion || output.contains("version") || output.contains("Version"))
    }

    @Test("HeaderView should display version in correct format")
    func testVersionFormat() {
        let view = HeaderView(terminalWidth: 80)
        let output = view.render()

        // Version should match semantic versioning pattern (e.g., "v1.2.3" or "1.2.3")
        let versionPattern = #/v?\d+\.\d+(\.\d+)?/#
        let hasValidVersion = output.contains(versionPattern)
        #expect(hasValidVersion)
    }

    @Test("HeaderView version should be configurable")
    func testConfigurableVersion() {
        let view = HeaderView(terminalWidth: 80, version: "2.0.0")
        let output = view.render()

        #expect(output.contains("2.0.0"))
    }
}

@Suite("HeaderView Timer Display")
struct HeaderViewTimerDisplayTests {

    @Test("HeaderView should display remaining time")
    func testDisplayRemainingTime() {
        let view = HeaderView(terminalWidth: 80)
        view.setRemainingTime("24:35")

        let output = view.render()

        #expect(output.contains("24:35"))
    }

    @Test("HeaderView should display time in MM:SS format")
    func testTimeFormat() {
        let view = HeaderView(terminalWidth: 80)
        view.setRemainingTime("05:00")

        let output = view.render()

        // Should show leading zero for single-digit minutes
        #expect(output.contains("05:00") || output.contains("5:00"))
    }

    @Test("HeaderView should update time dynamically")
    func testDynamicTimeUpdate() {
        let view = HeaderView(terminalWidth: 80)

        view.setRemainingTime("30:00")
        let output1 = view.render()
        #expect(output1.contains("30:00"))

        view.setRemainingTime("29:59")
        let output2 = view.render()
        #expect(output2.contains("29:59"))
    }

    @Test("HeaderView should display time label")
    func testTimeLabel() {
        let view = HeaderView(terminalWidth: 80)
        view.setRemainingTime("24:35")

        let output = view.render()

        // Should have a label like "Time Remaining" or "Remaining"
        #expect(output.contains("Time") || output.contains("Remaining") || output.contains("remaining"))
    }

    @Test("HeaderView should handle zero time")
    func testZeroTime() {
        let view = HeaderView(terminalWidth: 80)
        view.setRemainingTime("00:00")

        let output = view.render()

        #expect(output.contains("00:00") || output.contains("0:00"))
    }

    @Test("HeaderView should handle time over 99 minutes")
    func testLongTime() {
        let view = HeaderView(terminalWidth: 80)
        view.setRemainingTime("120:00")

        let output = view.render()

        #expect(output.contains("120:00"))
    }
}

@Suite("HeaderView Question Display")
struct HeaderViewQuestionDisplayTests {

    @Test("HeaderView should display interview question")
    func testDisplayQuestion() {
        let view = HeaderView(terminalWidth: 80)
        view.setQuestion("Design a URL shortener service")

        let output = view.render()

        #expect(output.contains("URL shortener") || output.contains("Design"))
    }

    @Test("HeaderView should truncate long questions")
    func testTruncateLongQuestion() {
        let view = HeaderView(terminalWidth: 60)
        let longQuestion = "Design a highly scalable distributed system that handles millions of requests per second with global consistency"

        view.setQuestion(longQuestion)
        let output = view.render()

        // Should truncate with ellipsis or similar
        let lines = output.split(separator: "\n")
        for line in lines {
            let strippedLine = stripANSI(String(line))
            #expect(strippedLine.count <= 60)
        }
    }

    @Test("HeaderView should wrap long questions")
    func testWrapLongQuestion() {
        let view = HeaderView(terminalWidth: 40)
        let longQuestion = "Design a real-time notification system"

        view.setQuestion(longQuestion)
        let output = view.render()

        // If wrapped, question content should span multiple parts
        let hasQuestion = output.contains("Design") && output.contains("notification")
        #expect(hasQuestion)
    }

    @Test("HeaderView should display question label")
    func testQuestionLabel() {
        let view = HeaderView(terminalWidth: 80)
        view.setQuestion("Design a cache")

        let output = view.render()

        #expect(output.contains("Question") || output.contains("Topic") || output.contains("Design"))
    }

    @Test("HeaderView should handle empty question")
    func testEmptyQuestion() {
        let view = HeaderView(terminalWidth: 80)
        view.setQuestion("")

        let output = view.render()

        // Should not crash and still render
        #expect(!output.isEmpty)
    }

    @Test("HeaderView should handle nil question")
    func testNilQuestion() {
        let view = HeaderView(terminalWidth: 80)
        // Question not set

        let output = view.render()

        // Should render without question or show placeholder
        #expect(!output.isEmpty)
    }
}

@Suite("HeaderView Styling")
struct HeaderViewStylingTests {

    @Test("HeaderView should use ANSI colors")
    func testUsesANSIColors() {
        let view = HeaderView(terminalWidth: 80)
        let output = view.render()

        // ANSI escape codes start with \033[ or \x1B[
        #expect(output.contains("\u{1B}["))
    }

    @Test("HeaderView should have plain text option")
    func testPlainTextOption() {
        let view = HeaderView(terminalWidth: 80)
        let output = view.render(useColors: false)

        // Should not contain ANSI escape codes
        #expect(!output.contains("\u{1B}["))
    }

    @Test("HeaderView should use box drawing characters")
    func testBoxDrawingCharacters() {
        let view = HeaderView(terminalWidth: 80)
        let output = view.render()

        // Unicode box drawing characters or ASCII alternatives
        let hasBoxChars = output.contains("-") ||
                         output.contains("|") ||
                         output.contains("+") ||
                         output.contains("=")
        #expect(hasBoxChars)
    }

    @Test("HeaderView should have consistent styling")
    func testConsistentStyling() {
        let view = HeaderView(terminalWidth: 80)
        view.setQuestion("Test")
        view.setRemainingTime("30:00")

        let output1 = view.render()
        let output2 = view.render()

        // Same input should produce same output
        #expect(output1 == output2)
    }
}

@Suite("HeaderView Size Adaptation")
struct HeaderViewSizeAdaptationTests {

    @Test("HeaderView should adapt to minimum width")
    func testMinimumWidth() {
        let view = HeaderView(terminalWidth: 30)
        let output = view.render()

        // Should still be functional at minimum width
        #expect(!output.isEmpty)

        let lines = output.split(separator: "\n")
        for line in lines {
            let strippedLine = stripANSI(String(line))
            #expect(strippedLine.count <= 30)
        }
    }

    @Test("HeaderView should adapt to very wide terminals")
    func testWideTerminal() {
        let view = HeaderView(terminalWidth: 200)
        let output = view.render()

        // Should render properly without excessive stretching
        #expect(!output.isEmpty)
    }

    @Test("HeaderView should update on terminal resize")
    func testTerminalResize() {
        let view = HeaderView(terminalWidth: 80)
        let output80 = view.render()

        view.setTerminalWidth(60)
        let output60 = view.render()

        // Different widths should produce different layouts
        #expect(output80 != output60)
    }
}

@Suite("HeaderView Rendering")
struct HeaderViewRenderingTests {

    @Test("HeaderView render should return non-empty string")
    func testRenderReturnsString() {
        let view = HeaderView(terminalWidth: 80)
        let output = view.render()

        #expect(!output.isEmpty)
    }

    @Test("HeaderView should render multiple lines")
    func testRenderMultipleLines() {
        let view = HeaderView(terminalWidth: 80)
        let output = view.render()

        let lineCount = output.split(separator: "\n").count
        #expect(lineCount > 1)
    }

    @Test("HeaderView should render consistently")
    func testConsistentRendering() {
        let view = HeaderView(terminalWidth: 80)
        view.setQuestion("Test question")
        view.setRemainingTime("25:00")

        let output1 = view.render()
        let output2 = view.render()

        #expect(output1 == output2)
    }

    @Test("HeaderView should clear previous content option")
    func testClearPreviousContent() {
        let view = HeaderView(terminalWidth: 80)
        let output = view.render(clearPrevious: true)

        // Should include cursor movement/clear sequences
        // Typically uses ANSI sequences to move cursor up or clear lines
        #expect(!output.isEmpty)
    }
}

// MARK: - Helper Functions

/// Strip ANSI escape sequences from a string for width measurement
private func stripANSI(_ string: String) -> String {
    var result = ""
    var inEscape = false

    for char in string {
        if char == "\u{1B}" {
            inEscape = true
        } else if inEscape {
            if char.isLetter || char == "~" || char == "@" {
                inEscape = false
            }
        } else {
            result.append(char)
        }
    }

    return result
}
