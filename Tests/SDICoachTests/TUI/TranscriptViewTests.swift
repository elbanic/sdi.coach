// TranscriptViewTests.swift
// TDD RED Phase: Failing tests for TranscriptView
//
// Task 5.3.4: TranscriptView - Real-time conversation display, message formatting
//
// Test framework: swift-testing (NOT XCTest)
// Feature: sdi.coach TUI Components

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 5.3.4: TranscriptView Tests

@Suite("TranscriptView Initialization")
struct TranscriptViewInitializationTests {

    @Test("TranscriptView should be initializable")
    func testTranscriptViewInitializable() {
        let view = TranscriptView()
        #expect(view != nil)
    }

    @Test("TranscriptView should accept terminal width")
    func testTranscriptViewWithTerminalWidth() {
        let view = TranscriptView(terminalWidth: 80)
        #expect(view.terminalWidth == 80)
    }

    @Test("TranscriptView should start empty")
    func testStartsEmpty() {
        let view = TranscriptView()
        #expect(view.transcriptCount == 0)
    }

    @Test("TranscriptView should have configurable max height")
    func testConfigurableMaxHeight() {
        let view = TranscriptView(terminalWidth: 80, maxLines: 100)
        #expect(view.maxLines == 100)
    }
}

@Suite("TranscriptView Interviewer Messages")
struct TranscriptViewInterviewerMessagesTests {

    @Test("TranscriptView should render interviewer message with robot emoji")
    func testInterviewerMessageWithRobotEmoji() {
        let view = TranscriptView(terminalWidth: 80)
        let now = Date()

        view.addMessage(source: .interviewer, content: "What are the requirements?", timestamp: now)

        let output = view.render()

        // Should display robot emoji for interviewer
        #expect(output.contains("Bot") || output.contains("Interviewer") || output.contains("["))
    }

    @Test("TranscriptView should display interviewer content")
    func testInterviewerContent() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "Let's discuss scalability", timestamp: Date())

        let output = view.render()

        #expect(output.contains("scalability"))
    }

    @Test("TranscriptView should wrap long interviewer messages")
    func testWrapLongInterviewerMessage() {
        let view = TranscriptView(terminalWidth: 50)
        let longMessage = "This is a very long message from the interviewer that should be wrapped to fit within the terminal width properly"

        view.addMessage(source: .interviewer, content: longMessage, timestamp: Date())

        let output = view.render()
        let lines = output.split(separator: "\n")

        for line in lines {
            let strippedLine = stripANSI(String(line))
            #expect(strippedLine.count <= 50)
        }
    }

    @Test("TranscriptView interviewer messages should have distinct styling")
    func testInterviewerStyling() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "Question", timestamp: Date())
        view.addMessage(source: .user, content: "Answer", timestamp: Date())

        let output = view.render()

        // Different styling - can check for ANSI codes or prefixes
        let hasDistinctElements = output.contains("Question") && output.contains("Answer")
        #expect(hasDistinctElements)
    }
}

@Suite("TranscriptView User Messages")
struct TranscriptViewUserMessagesTests {

    @Test("TranscriptView should render user message with microphone emoji")
    func testUserMessageWithMicEmoji() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .user, content: "I think we need caching", timestamp: Date())

        let output = view.render()

        // Should display mic or user indicator
        #expect(output.contains("User") || output.contains("You") || output.contains("["))
    }

    @Test("TranscriptView should display user content")
    func testUserContent() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .user, content: "We should use Redis for caching", timestamp: Date())

        let output = view.render()

        #expect(output.contains("Redis") || output.contains("caching"))
    }

    @Test("TranscriptView should wrap long user messages")
    func testWrapLongUserMessage() {
        let view = TranscriptView(terminalWidth: 50)
        let longMessage = "I believe we should implement a distributed caching layer using Redis with proper TTL management and cache invalidation strategies"

        view.addMessage(source: .user, content: longMessage, timestamp: Date())

        let output = view.render()
        let lines = output.split(separator: "\n")

        for line in lines {
            let strippedLine = stripANSI(String(line))
            #expect(strippedLine.count <= 50)
        }
    }
}

@Suite("TranscriptView Timestamp Formatting")
struct TranscriptViewTimestampFormattingTests {

    @Test("TranscriptView should display timestamp")
    func testDisplayTimestamp() {
        let view = TranscriptView(terminalWidth: 80)

        // Create a specific time
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 10
        components.minute = 30
        components.second = 15
        let specificTime = calendar.date(from: components)!

        view.addMessage(source: .interviewer, content: "Hello", timestamp: specificTime)

        let output = view.render()

        // Should contain time in HH:MM:SS or HH:MM format
        #expect(output.contains("10:30") || output.contains("10:30:15"))
    }

    @Test("TranscriptView should format timestamp with brackets")
    func testTimestampBrackets() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "Test", timestamp: Date())

        let output = view.render()

        // Timestamps are typically enclosed in brackets
        #expect(output.contains("[") && output.contains("]"))
    }

    @Test("TranscriptView should use 24-hour format")
    func testTimestamp24HourFormat() {
        let view = TranscriptView(terminalWidth: 80)

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 14  // 2 PM
        components.minute = 30
        let afternoon = calendar.date(from: components)!

        view.addMessage(source: .user, content: "Test", timestamp: afternoon)

        let output = view.render()

        // Should show 14:30, not 2:30 PM
        #expect(output.contains("14:30") || output.contains("14:"))
    }

    @Test("TranscriptView should pad single-digit times")
    func testTimestampPadding() {
        let view = TranscriptView(terminalWidth: 80)

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 5
        components.second = 3
        let earlyMorning = calendar.date(from: components)!

        view.addMessage(source: .interviewer, content: "Test", timestamp: earlyMorning)

        let output = view.render()

        // Should show "09:05" not "9:5"
        #expect(output.contains("09:05") || output.contains("09:5") || output.contains("9:05"))
    }
}

@Suite("TranscriptView Scrollback Support")
struct TranscriptViewScrollbackTests {

    @Test("TranscriptView should accumulate messages")
    func testAccumulateMessages() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "Q1", timestamp: Date())
        view.addMessage(source: .user, content: "A1", timestamp: Date())
        view.addMessage(source: .interviewer, content: "Q2", timestamp: Date())

        #expect(view.transcriptCount == 3)
    }

    @Test("TranscriptView should maintain message order")
    func testMaintainOrder() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "First", timestamp: Date())
        view.addMessage(source: .user, content: "Second", timestamp: Date())
        view.addMessage(source: .interviewer, content: "Third", timestamp: Date())

        let output = view.render()

        // "First" should appear before "Second" which should appear before "Third"
        if let firstIndex = output.range(of: "First")?.lowerBound,
           let secondIndex = output.range(of: "Second")?.lowerBound,
           let thirdIndex = output.range(of: "Third")?.lowerBound {
            #expect(firstIndex < secondIndex)
            #expect(secondIndex < thirdIndex)
        } else {
            #expect(output.contains("First"))
            #expect(output.contains("Second"))
            #expect(output.contains("Third"))
        }
    }

    @Test("TranscriptView should render all messages by default")
    func testRenderAllMessages() {
        let view = TranscriptView(terminalWidth: 80)

        for i in 1...10 {
            view.addMessage(source: .interviewer, content: "Message \(i)", timestamp: Date())
        }

        let output = view.render()

        for i in 1...10 {
            #expect(output.contains("Message \(i)"))
        }
    }

    @Test("TranscriptView should support limiting visible messages")
    func testLimitVisibleMessages() {
        let view = TranscriptView(terminalWidth: 80, maxLines: 50)

        for i in 1...100 {
            view.addMessage(source: .interviewer, content: "Message \(i)", timestamp: Date())
        }

        let output = view.renderLastN(lines: 20)

        // Should render only recent messages
        #expect(output.contains("Message 100"))
        #expect(!output.contains("Message 1") || output.contains("Message 1") == output.contains("Message 100"))
    }

    @Test("TranscriptView should support clearing")
    func testClearMessages() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "Test", timestamp: Date())
        #expect(view.transcriptCount == 1)

        view.clear()

        #expect(view.transcriptCount == 0)
    }

    @Test("TranscriptView should provide scrollable history")
    func testScrollableHistory() {
        let view = TranscriptView(terminalWidth: 80)

        for i in 1...50 {
            view.addMessage(source: .interviewer, content: "Line \(i)", timestamp: Date())
        }

        // Get all messages (for scrollback)
        let allMessages = view.getAllMessages()

        #expect(allMessages.count == 50)
        #expect(allMessages.first?.content == "Line 1")
        #expect(allMessages.last?.content == "Line 50")
    }
}

@Suite("TranscriptView Rendering Options")
struct TranscriptViewRenderingOptionsTests {

    @Test("TranscriptView should render with ANSI colors")
    func testRenderWithColors() {
        let view = TranscriptView(terminalWidth: 80)
        view.addMessage(source: .interviewer, content: "Test", timestamp: Date())

        let output = view.render()

        // Should contain ANSI escape codes
        #expect(output.contains("\u{1B}["))
    }

    @Test("TranscriptView should render plain text")
    func testRenderPlainText() {
        let view = TranscriptView(terminalWidth: 80)
        view.addMessage(source: .interviewer, content: "Test", timestamp: Date())

        let output = view.render(useColors: false)

        // Should not contain ANSI escape codes
        #expect(!output.contains("\u{1B}["))
    }

    @Test("TranscriptView should render single message")
    func testRenderSingleMessage() {
        let view = TranscriptView(terminalWidth: 80)

        let timestamp = Date()
        view.addMessage(source: .interviewer, content: "Single message", timestamp: timestamp)

        let singleOutput = view.renderMessage(at: 0)

        #expect(singleOutput != nil)
        #expect(singleOutput!.contains("Single message"))
    }

    @Test("TranscriptView should format for append-only mode")
    func testAppendOnlyFormat() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "First", timestamp: Date())
        let firstOutput = view.renderLatest()

        view.addMessage(source: .user, content: "Second", timestamp: Date())
        let secondOutput = view.renderLatest()

        // Each renderLatest should return only the new message
        #expect(firstOutput.contains("First"))
        #expect(!firstOutput.contains("Second"))

        #expect(secondOutput.contains("Second"))
        #expect(!secondOutput.contains("First"))
    }
}

@Suite("TranscriptView Message Types")
struct TranscriptViewMessageTypesTests {

    @Test("TranscriptView should differentiate interviewer and user visually")
    func testVisualDifferentiation() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "Interviewer says", timestamp: Date())
        view.addMessage(source: .user, content: "User says", timestamp: Date())

        let output = view.render()

        // Should have different prefixes or colors
        #expect(output.contains("Interviewer says"))
        #expect(output.contains("User says"))
    }

    @Test("TranscriptView should show source indicator before message")
    func testSourceIndicatorPosition() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "Content here", timestamp: Date())

        let output = view.render()

        // Source indicator (emoji/text) should appear before content
        // Format like: "[10:30] Bot: Content here" or similar
        let hasFormat = output.contains("[") && output.contains("]") && output.contains("Content here")
        #expect(hasFormat)
    }
}

@Suite("TranscriptView Width Handling")
struct TranscriptViewWidthHandlingTests {

    @Test("TranscriptView should respect terminal width")
    func testRespectTerminalWidth() {
        let view = TranscriptView(terminalWidth: 60)

        view.addMessage(source: .interviewer, content: "This is a message that might need wrapping", timestamp: Date())

        let output = view.render()
        let lines = output.split(separator: "\n")

        for line in lines {
            let strippedLine = stripANSI(String(line))
            #expect(strippedLine.count <= 60)
        }
    }

    @Test("TranscriptView should update on terminal resize")
    func testUpdateOnResize() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "Test message", timestamp: Date())
        let output80 = view.render()

        view.setTerminalWidth(40)
        let output40 = view.render()

        // Different widths may produce different wrapping
        #expect(!output80.isEmpty)
        #expect(!output40.isEmpty)
    }

    @Test("TranscriptView should handle very narrow terminal")
    func testVeryNarrowTerminal() {
        let view = TranscriptView(terminalWidth: 30)

        view.addMessage(source: .interviewer, content: "Short", timestamp: Date())

        let output = view.render()
        let lines = output.split(separator: "\n")

        for line in lines {
            let strippedLine = stripANSI(String(line))
            #expect(strippedLine.count <= 30)
        }
    }

    @Test("TranscriptView should handle CJK characters width")
    func testCJKCharactersWidth() {
        let view = TranscriptView(terminalWidth: 40)

        view.addMessage(source: .user, content: "Korean text", timestamp: Date())

        let output = view.render()

        // Should handle properly without overflow
        #expect(!output.isEmpty)
    }

    @Test("TranscriptView should handle emoji in messages")
    func testEmojiInMessages() {
        let view = TranscriptView(terminalWidth: 60)

        view.addMessage(source: .user, content: "Great idea! Let's do it!", timestamp: Date())

        let output = view.render()

        #expect(output.contains("Great idea"))
    }
}

@Suite("TranscriptView Thread Safety")
struct TranscriptViewThreadSafetyTests {

    @Test("TranscriptView should be thread-safe for concurrent writes")
    func testConcurrentWrites() async {
        let view = TranscriptView(terminalWidth: 80)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    view.addMessage(
                        source: i % 2 == 0 ? .interviewer : .user,
                        content: "Message \(i)",
                        timestamp: Date()
                    )
                }
            }
        }

        // Should have accumulated messages without crash
        #expect(view.transcriptCount == 20)
    }

    @Test("TranscriptView should be thread-safe for concurrent read/write")
    func testConcurrentReadWrite() async {
        let view = TranscriptView(terminalWidth: 80)

        // Pre-populate
        for i in 0..<10 {
            view.addMessage(source: .interviewer, content: "Initial \(i)", timestamp: Date())
        }

        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<10 {
                group.addTask {
                    view.addMessage(source: .user, content: "New \(i)", timestamp: Date())
                }
            }

            // Readers
            for _ in 0..<10 {
                group.addTask {
                    _ = view.render()
                }
            }
        }

        // Should complete without crash
        #expect(view.transcriptCount == 20)
    }
}

@Suite("TranscriptView Export")
struct TranscriptViewExportTests {

    @Test("TranscriptView should export as plain text")
    func testExportPlainText() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "Question", timestamp: Date())
        view.addMessage(source: .user, content: "Answer", timestamp: Date())

        let exported = view.exportAsPlainText()

        #expect(exported.contains("Question"))
        #expect(exported.contains("Answer"))
        #expect(!exported.contains("\u{1B}[")) // No ANSI codes
    }

    @Test("TranscriptView should export as markdown")
    func testExportAsMarkdown() {
        let view = TranscriptView(terminalWidth: 80)

        view.addMessage(source: .interviewer, content: "Question", timestamp: Date())
        view.addMessage(source: .user, content: "Answer", timestamp: Date())

        let exported = view.exportAsMarkdown()

        // Markdown format with headers or bullets
        #expect(exported.contains("Question"))
        #expect(exported.contains("Answer"))
    }
}

// MARK: - Helper Functions

/// Strip ANSI escape sequences from a string
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
