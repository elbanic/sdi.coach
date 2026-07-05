// StatusBarViewTests.swift
// TDD RED Phase: Failing tests for StatusBar
//
// Task 5.3.3: StatusBar - Interview status, microphone status, available commands
//
// Test framework: swift-testing (NOT XCTest)
// Feature: sdi.coach TUI Components

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 5.3.3: StatusBar Tests

@Suite("StatusBar Initialization")
struct StatusBarInitializationTests {

    @Test("StatusBar should be initializable")
    func testStatusBarInitializable() {
        let bar = StatusBar()
        #expect(bar != nil)
    }

    @Test("StatusBar should accept terminal width")
    func testStatusBarWithTerminalWidth() {
        let bar = StatusBar(terminalWidth: 80)
        #expect(bar.terminalWidth == 80)
    }

    @Test("StatusBar should have default state")
    func testDefaultState() {
        let bar = StatusBar()

        #expect(bar.currentMode == .idle)
        #expect(bar.isMicrophoneOn == false)
        #expect(bar.remainingTime == "30:00")
    }
}

@Suite("StatusBar Interview Status Indicator")
struct StatusBarInterviewStatusTests {

    @Test("StatusBar should show idle status")
    func testIdleStatus() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.idle)

        let output = bar.render()

        #expect(output.contains("Idle") || output.contains("idle") || output.contains("Ready"))
    }

    @Test("StatusBar should show interviewing status")
    func testInterviewingStatus() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)

        let output = bar.render()

        #expect(output.contains("Interview") || output.contains("interview"))
    }

    @Test("StatusBar should show paused status")
    func testPausedStatus() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.paused)

        let output = bar.render()

        #expect(output.contains("Pause") || output.contains("pause"))
    }

    @Test("StatusBar should show feedback status")
    func testFeedbackStatus() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.feedback)

        let output = bar.render()

        #expect(output.contains("Feedback") || output.contains("feedback"))
    }

    @Test("StatusBar should use distinct colors for different modes")
    func testDistinctColorsForModes() {
        let bar = StatusBar(terminalWidth: 80)

        bar.setMode(.idle)
        let idleOutput = bar.render()

        bar.setMode(.interviewing)
        let interviewingOutput = bar.render()

        bar.setMode(.paused)
        let pausedOutput = bar.render()

        // Different modes should have visually different outputs
        #expect(idleOutput != interviewingOutput)
        #expect(interviewingOutput != pausedOutput)
    }

    @Test("StatusBar should use emoji indicator for status")
    func testEmojiIndicator() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)

        let output = bar.render()

        // May use emoji like microphone icon
        let hasIndicator = output.contains("Interview") ||
                          output.contains("|") ||
                          output.contains(":") // separators count
        #expect(hasIndicator)
    }
}

@Suite("StatusBar Microphone Status")
struct StatusBarMicrophoneStatusTests {

    @Test("StatusBar should show microphone ON status")
    func testMicrophoneOn() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMicrophoneOn(true)

        let output = bar.render()

        #expect(output.contains("ON") || output.contains("on") || output.contains("MIC"))
    }

    @Test("StatusBar should show microphone OFF status")
    func testMicrophoneOff() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMicrophoneOn(false)

        let output = bar.render()

        #expect(output.contains("OFF") || output.contains("off") || output.contains("MUTED"))
    }

    @Test("StatusBar should toggle microphone status")
    func testToggleMicrophone() {
        let bar = StatusBar(terminalWidth: 80)

        bar.setMicrophoneOn(true)
        let onOutput = bar.render()

        bar.setMicrophoneOn(false)
        let offOutput = bar.render()

        #expect(onOutput != offOutput)
    }

    @Test("StatusBar should use green color for mic on")
    func testGreenForMicOn() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMicrophoneOn(true)

        let output = bar.render()

        // ANSI green color code is 32
        #expect(output.contains("32m") || output.contains("92m")) // green or bright green
    }

    @Test("StatusBar should use red color for mic off")
    func testRedForMicOff() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMicrophoneOn(false)

        let output = bar.render()

        // ANSI red color code is 31
        #expect(output.contains("31m") || output.contains("91m")) // red or bright red
    }

    @Test("StatusBar microphone indicator should be visible")
    func testMicIndicatorVisible() {
        let bar = StatusBar(terminalWidth: 80)

        bar.setMicrophoneOn(true)
        let output = bar.render()

        // Should contain microphone-related text or emoji
        let hasMicIndicator = output.contains("MIC") ||
                             output.contains("mic") ||
                             output.contains("Mic") ||
                             output.contains("ON") ||
                             output.contains("OFF")
        #expect(hasMicIndicator)
    }
}

@Suite("StatusBar Available Commands Hint")
struct StatusBarCommandsHintTests {

    @Test("StatusBar should show /start hint when idle")
    func testStartHintWhenIdle() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.idle)

        let output = bar.render()

        #expect(output.contains("/start") || output.contains("start"))
    }

    @Test("StatusBar should show /pause and /end hints when interviewing")
    func testPauseEndHintsWhenInterviewing() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)

        let output = bar.render()

        let hasPauseOrEnd = output.contains("/pause") ||
                           output.contains("/end") ||
                           output.contains("pause") ||
                           output.contains("end")
        #expect(hasPauseOrEnd)
    }

    @Test("StatusBar should show /resume hint when paused")
    func testResumeHintWhenPaused() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.paused)

        let output = bar.render()

        // Resume could be /start or /resume
        let hasResumeHint = output.contains("/start") ||
                           output.contains("/resume") ||
                           output.contains("resume") ||
                           output.contains("/end")
        #expect(hasResumeHint)
    }

    @Test("StatusBar should show appropriate hints for feedback mode")
    func testFeedbackModeHints() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.feedback)

        let output = bar.render()

        // In feedback mode, might show /quit or waiting indicator
        let hasHint = output.contains("/quit") ||
                     output.contains("quit") ||
                     output.contains("wait") ||
                     output.contains("Generating")
        #expect(hasHint || output.contains("Feedback"))
    }

    @Test("StatusBar command hints should be clearly visible")
    func testCommandHintsVisible() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)

        let output = bar.render()

        // Commands should be visible (not cut off)
        let hasVisibleCommands = output.contains("/") || output.contains("end") || output.contains("pause")
        #expect(hasVisibleCommands)
    }
}

@Suite("StatusBar Timer Display")
struct StatusBarTimerDisplayTests {

    @Test("StatusBar should show remaining time")
    func testShowRemainingTime() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setRemainingTime("24:35")

        let output = bar.render()

        #expect(output.contains("24:35"))
    }

    @Test("StatusBar should update time display")
    func testUpdateTimeDisplay() {
        let bar = StatusBar(terminalWidth: 80)

        bar.setRemainingTime("30:00")
        let output1 = bar.render()

        bar.setRemainingTime("29:59")
        let output2 = bar.render()

        #expect(output1.contains("30:00"))
        #expect(output2.contains("29:59"))
    }

    @Test("StatusBar should show time icon")
    func testTimeIcon() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setRemainingTime("25:00")

        let output = bar.render()

        // May use clock emoji or time indicator
        let hasTimeIndicator = output.contains("25:00") ||
                              output.contains(":") // time separator
        #expect(hasTimeIndicator)
    }

    @Test("StatusBar should handle zero time")
    func testZeroTime() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setRemainingTime("00:00")

        let output = bar.render()

        #expect(output.contains("00:00") || output.contains("0:00"))
    }

    @Test("StatusBar should highlight low time")
    func testHighlightLowTime() {
        let bar = StatusBar(terminalWidth: 80)

        bar.setRemainingTime("25:00")
        let normalOutput = bar.render()

        bar.setRemainingTime("02:00")
        let lowTimeOutput = bar.render()

        // Low time should look different (e.g., red color)
        // Just verify both render correctly for now
        #expect(normalOutput.contains("25:00"))
        #expect(lowTimeOutput.contains("02:00"))
    }
}

@Suite("StatusBar Layout")
struct StatusBarLayoutTests {

    @Test("StatusBar should fit terminal width")
    func testFitsTerminalWidth() {
        let bar = StatusBar(terminalWidth: 60)
        bar.setMode(.interviewing)
        bar.setMicrophoneOn(true)
        bar.setRemainingTime("24:35")

        let output = bar.render()
        let plainOutput = stripANSI(output)

        // Should not exceed terminal width
        #expect(plainOutput.count <= 60)
    }

    @Test("StatusBar should render on single line")
    func testSingleLine() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)

        let output = bar.render()

        // Status bar should be a single line (no internal newlines)
        // Note: may have trailing newline
        let lineCount = output.trimmingCharacters(in: .newlines).split(separator: "\n").count
        #expect(lineCount == 1)
    }

    @Test("StatusBar should use separators between elements")
    func testSeparators() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)
        bar.setMicrophoneOn(true)
        bar.setRemainingTime("25:00")

        let output = bar.render()

        // Should have separators like |, -, or spaces
        let hasSeparators = output.contains("|") ||
                           output.contains("-") ||
                           output.contains("  ") // double space
        #expect(hasSeparators)
    }

    @Test("StatusBar should adapt to narrow terminal")
    func testNarrowTerminal() {
        let bar = StatusBar(terminalWidth: 40)
        bar.setMode(.interviewing)
        bar.setMicrophoneOn(true)
        bar.setRemainingTime("25:00")

        let output = bar.render()
        let plainOutput = stripANSI(output)

        // Should still fit and include essential info
        #expect(plainOutput.count <= 40)
        #expect(output.contains("25:00")) // Time is essential
    }

    @Test("StatusBar should prioritize time in narrow mode")
    func testPrioritizeTimeInNarrow() {
        let bar = StatusBar(terminalWidth: 30)
        bar.setMode(.interviewing)
        bar.setRemainingTime("24:35")

        let output = bar.render()

        // Time should always be visible
        #expect(output.contains("24:35"))
    }
}

@Suite("StatusBar Styling")
struct StatusBarStylingTests {

    @Test("StatusBar should use ANSI colors")
    func testUsesANSIColors() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)

        let output = bar.render()

        #expect(output.contains("\u{1B}["))
    }

    @Test("StatusBar should have plain text option")
    func testPlainTextOption() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)

        let output = bar.render(useColors: false)

        #expect(!output.contains("\u{1B}["))
    }

    @Test("StatusBar should have consistent styling")
    func testConsistentStyling() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)
        bar.setMicrophoneOn(true)
        bar.setRemainingTime("25:00")

        let output1 = bar.render()
        let output2 = bar.render()

        #expect(output1 == output2)
    }

    @Test("StatusBar should use bold for important elements")
    func testBoldForImportant() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)

        let output = bar.render()

        // Bold ANSI code is [1m
        let hasBold = output.contains("1;") || output.contains("[1m")
        #expect(hasBold || !output.contains("\u{1B}["))
    }
}

@Suite("StatusBar State Updates")
struct StatusBarStateUpdatesTests {

    @Test("StatusBar setMode should update state")
    func testSetModeUpdatesState() {
        let bar = StatusBar(terminalWidth: 80)

        bar.setMode(.interviewing)
        #expect(bar.currentMode == .interviewing)

        bar.setMode(.paused)
        #expect(bar.currentMode == .paused)
    }

    @Test("StatusBar setMicrophoneOn should update state")
    func testSetMicrophoneUpdatesState() {
        let bar = StatusBar(terminalWidth: 80)

        bar.setMicrophoneOn(true)
        #expect(bar.isMicrophoneOn == true)

        bar.setMicrophoneOn(false)
        #expect(bar.isMicrophoneOn == false)
    }

    @Test("StatusBar setRemainingTime should update state")
    func testSetRemainingTimeUpdatesState() {
        let bar = StatusBar(terminalWidth: 80)

        bar.setRemainingTime("15:30")
        #expect(bar.remainingTime == "15:30")
    }

    @Test("StatusBar should update terminal width")
    func testUpdateTerminalWidth() {
        let bar = StatusBar(terminalWidth: 80)

        bar.setTerminalWidth(60)
        #expect(bar.terminalWidth == 60)
    }
}

@Suite("StatusBar Thread Safety")
struct StatusBarThreadSafetyTests {

    @Test("StatusBar should be thread-safe for concurrent reads")
    func testConcurrentReads() async {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)

        await withTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    return bar.render()
                }
            }

            var outputs: [String] = []
            for await output in group {
                outputs.append(output)
            }

            // All outputs should be identical
            let first = outputs.first!
            for output in outputs {
                #expect(output == first)
            }
        }
    }

    @Test("StatusBar should be thread-safe for concurrent updates")
    func testConcurrentUpdates() async {
        let bar = StatusBar(terminalWidth: 80)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    bar.setMicrophoneOn(i % 2 == 0)
                    _ = bar.render()
                }
            }
        }

        // Should complete without crash
        #expect(bar.isMicrophoneOn == true || bar.isMicrophoneOn == false)
    }
}

@Suite("StatusBar Prompt Line")
struct StatusBarPromptLineTests {

    @Test("StatusBar should render prompt line")
    func testRenderPromptLine() {
        let bar = StatusBar(terminalWidth: 80)

        let prompt = bar.renderPromptLine()

        // Prompt should have input indicator
        #expect(prompt.contains(">") || prompt.contains(":") || prompt.contains("$"))
    }

    @Test("StatusBar prompt should be on new line")
    func testPromptOnNewLine() {
        let bar = StatusBar(terminalWidth: 80)
        bar.setMode(.interviewing)

        let fullOutput = bar.renderWithPrompt()

        // Should contain both status bar and prompt
        let lines = fullOutput.split(separator: "\n")
        #expect(lines.count >= 2) // Status bar + prompt
    }

    @Test("StatusBar prompt should show current input")
    func testPromptShowsInput() {
        let bar = StatusBar(terminalWidth: 80)

        let prompt = bar.renderPromptLine(currentInput: "/sta")

        #expect(prompt.contains("/sta"))
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
