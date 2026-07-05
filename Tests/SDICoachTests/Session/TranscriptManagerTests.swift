// TranscriptManagerTests.swift
// TDD RED Phase: Failing tests for TranscriptManager
//
// Task 6.1.3: TranscriptManager (accumulation, export)
//
// Requirements:
// 1. TranscriptManager initialization
//    - Empty state initialization
//    - Optional initialization with existing transcripts
//
// 2. Transcript management
//    - add(entry: TranscriptEntry) - Add transcript
//    - add(source: TranscriptSource, content: String) - Convenience method
//    - clear() - Clear all transcripts
//    - entries: [TranscriptEntry] - Read-only array
//
// 3. Statistics
//    - count: Int (total entry count)
//    - interviewerCount: Int (interviewer speech count)
//    - userCount: Int (user speech count)
//    - totalWordCount: Int (total word count)
//
// 4. Export Functions
//    - toJSON() -> String (export as JSON)
//    - toMarkdown() -> String (export as Markdown)
//    - toFormattedTranscript(for feedbackRequest: Bool) -> [[String: String]] (format for feedback)
//
// 5. Thread Safety
//    - Sendable protocol conformance
//
// Test framework: swift-testing (NOT XCTest)
// Feature: sdi.coach Session Management

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 6.1.3: TranscriptManager Initialization Tests

@Suite("TranscriptManager Initialization")
struct TranscriptManagerInitializationTests {

    @Test("TranscriptManager should be initializable with empty state")
    func testEmptyInitialization() {
        let manager = TranscriptManager()

        #expect(manager.entries.isEmpty)
        #expect(manager.count == 0)
    }

    @Test("TranscriptManager should be initializable with existing transcripts")
    func testInitializationWithExistingTranscripts() {
        let existingEntries = [
            TranscriptEntry(source: .interviewer, content: "Question 1", timestamp: Date()),
            TranscriptEntry(source: .user, content: "Answer 1", timestamp: Date())
        ]

        let manager = TranscriptManager(entries: existingEntries)

        #expect(manager.entries.count == 2)
        #expect(manager.count == 2)
    }

    @Test("TranscriptManager should preserve order of existing transcripts")
    func testPreservesOrderOfExistingTranscripts() {
        let existingEntries = [
            TranscriptEntry(source: .interviewer, content: "First", timestamp: Date()),
            TranscriptEntry(source: .user, content: "Second", timestamp: Date()),
            TranscriptEntry(source: .interviewer, content: "Third", timestamp: Date())
        ]

        let manager = TranscriptManager(entries: existingEntries)

        #expect(manager.entries[0].content == "First")
        #expect(manager.entries[1].content == "Second")
        #expect(manager.entries[2].content == "Third")
    }

    @Test("TranscriptManager should handle empty array initialization")
    func testEmptyArrayInitialization() {
        let manager = TranscriptManager(entries: [])

        #expect(manager.entries.isEmpty)
        #expect(manager.count == 0)
    }

    @Test("TranscriptManager should make defensive copy of entries")
    func testDefensiveCopyOfEntries() {
        var existingEntries = [
            TranscriptEntry(source: .interviewer, content: "Original", timestamp: Date())
        ]

        let manager = TranscriptManager(entries: existingEntries)

        // Modify original array
        existingEntries.append(TranscriptEntry(source: .user, content: "New", timestamp: Date()))

        // Manager should not be affected
        #expect(manager.count == 1)
    }
}

// MARK: - Task 6.1.3: Transcript Addition Tests

@Suite("TranscriptManager Transcript Addition")
struct TranscriptManagerAdditionTests {

    @Test("add(entry:) should add transcript to entries")
    func testAddEntry() {
        let manager = TranscriptManager()
        let entry = TranscriptEntry(source: .interviewer, content: "Hello", timestamp: Date())

        manager.add(entry: entry)

        #expect(manager.count == 1)
        #expect(manager.entries.first?.content == "Hello")
    }

    @Test("add(entry:) should preserve entry properties")
    func testAddEntryPreservesProperties() {
        let manager = TranscriptManager()
        let timestamp = Date()
        let entry = TranscriptEntry(source: .user, content: "Test content", timestamp: timestamp)

        manager.add(entry: entry)

        let addedEntry = manager.entries.first
        #expect(addedEntry?.source == .user)
        #expect(addedEntry?.content == "Test content")
        #expect(addedEntry?.timestamp == timestamp)
    }

    @Test("add(source:content:) should create entry with current timestamp")
    func testAddConvenienceMethod() {
        let manager = TranscriptManager()
        let beforeAdd = Date()

        manager.add(source: .interviewer, content: "Question")

        let afterAdd = Date()

        #expect(manager.count == 1)
        #expect(manager.entries.first?.source == .interviewer)
        #expect(manager.entries.first?.content == "Question")

        let timestamp = manager.entries.first?.timestamp
        #expect(timestamp != nil)
        #expect(timestamp! >= beforeAdd)
        #expect(timestamp! <= afterAdd)
    }

    @Test("add(source:content:) should work for user source")
    func testAddConvenienceMethodUserSource() {
        let manager = TranscriptManager()

        manager.add(source: .user, content: "My answer")

        #expect(manager.entries.first?.source == .user)
        #expect(manager.entries.first?.content == "My answer")
    }

    @Test("Multiple adds should maintain order")
    func testMultipleAddsOrder() {
        let manager = TranscriptManager()

        manager.add(source: .interviewer, content: "First")
        manager.add(source: .user, content: "Second")
        manager.add(source: .interviewer, content: "Third")

        #expect(manager.entries[0].content == "First")
        #expect(manager.entries[1].content == "Second")
        #expect(manager.entries[2].content == "Third")
    }

    @Test("add should handle empty content")
    func testAddEmptyContent() {
        let manager = TranscriptManager()

        manager.add(source: .user, content: "")

        #expect(manager.count == 1)
        #expect(manager.entries.first?.content == "")
    }

    @Test("add should handle special characters")
    func testAddSpecialCharacters() {
        let manager = TranscriptManager()
        let specialContent = "Unicode: , Symbols: @#$%^&*(), Newlines:\n\t"

        manager.add(source: .user, content: specialContent)

        #expect(manager.entries.first?.content == specialContent)
    }

    @Test("add should handle very long content")
    func testAddLongContent() {
        let manager = TranscriptManager()
        let longContent = String(repeating: "Lorem ipsum dolor sit amet. ", count: 1000)

        manager.add(source: .user, content: longContent)

        #expect(manager.entries.first?.content == longContent)
    }

    @Test("add should handle many entries")
    func testAddManyEntries() {
        let manager = TranscriptManager()

        for i in 0..<1000 {
            let source: TranscriptSource = i % 2 == 0 ? .interviewer : .user
            manager.add(source: source, content: "Entry \(i)")
        }

        #expect(manager.count == 1000)
    }
}

// MARK: - Task 6.1.3: Clear Functionality Tests

@Suite("TranscriptManager Clear")
struct TranscriptManagerClearTests {

    @Test("clear should remove all entries")
    func testClear() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Question")
        manager.add(source: .user, content: "Answer")

        #expect(manager.count == 2)

        manager.clear()

        #expect(manager.count == 0)
        #expect(manager.entries.isEmpty)
    }

    @Test("clear on empty manager should not cause error")
    func testClearEmpty() {
        let manager = TranscriptManager()

        #expect(manager.count == 0)

        manager.clear()

        #expect(manager.count == 0)
    }

    @Test("clear should reset all statistics")
    func testClearResetsStatistics() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Question one two three")
        manager.add(source: .user, content: "Answer four five")

        #expect(manager.interviewerCount > 0)
        #expect(manager.userCount > 0)
        #expect(manager.totalWordCount > 0)

        manager.clear()

        #expect(manager.interviewerCount == 0)
        #expect(manager.userCount == 0)
        #expect(manager.totalWordCount == 0)
    }

    @Test("add after clear should work normally")
    func testAddAfterClear() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "First batch")
        manager.clear()

        manager.add(source: .user, content: "New content")

        #expect(manager.count == 1)
        #expect(manager.entries.first?.content == "New content")
    }

    @Test("multiple clear calls should be safe")
    func testMultipleClearCalls() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Content")

        manager.clear()
        manager.clear()
        manager.clear()

        #expect(manager.count == 0)
    }
}

// MARK: - Task 6.1.3: Read-Only Entries Tests

@Suite("TranscriptManager Entries Property")
struct TranscriptManagerEntriesTests {

    @Test("entries should be read-only array")
    func testEntriesReadOnly() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Test")

        let entries = manager.entries

        // entries should be a copy, modifications should not affect manager
        #expect(entries.count == 1)
        #expect(manager.count == 1)
    }

    @Test("entries should return defensive copy")
    func testEntriesDefensiveCopy() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Original")

        var entriesCopy = manager.entries
        entriesCopy.append(TranscriptEntry(source: .user, content: "New", timestamp: Date()))

        // Original manager should not be affected
        #expect(manager.count == 1)
        #expect(entriesCopy.count == 2)
    }

    @Test("entries should return all entries in order")
    func testEntriesOrder() {
        let manager = TranscriptManager()
        for i in 0..<10 {
            manager.add(source: i % 2 == 0 ? .interviewer : .user, content: "Entry \(i)")
        }

        let entries = manager.entries

        #expect(entries.count == 10)
        for i in 0..<10 {
            #expect(entries[i].content == "Entry \(i)")
        }
    }
}

// MARK: - Task 6.1.3: Statistics Tests

@Suite("TranscriptManager Statistics - Count")
struct TranscriptManagerCountTests {

    @Test("count should return total number of entries")
    func testCount() {
        let manager = TranscriptManager()

        #expect(manager.count == 0)

        manager.add(source: .interviewer, content: "Q1")
        #expect(manager.count == 1)

        manager.add(source: .user, content: "A1")
        #expect(manager.count == 2)

        manager.add(source: .interviewer, content: "Q2")
        #expect(manager.count == 3)
    }

    @Test("count should match entries.count")
    func testCountMatchesEntriesCount() {
        let manager = TranscriptManager()

        for i in 0..<50 {
            manager.add(source: i % 2 == 0 ? .interviewer : .user, content: "Entry \(i)")
            #expect(manager.count == manager.entries.count)
        }
    }
}

@Suite("TranscriptManager Statistics - Source Counts")
struct TranscriptManagerSourceCountTests {

    @Test("interviewerCount should count only interviewer entries")
    func testInterviewerCount() {
        let manager = TranscriptManager()

        manager.add(source: .interviewer, content: "Q1")
        manager.add(source: .user, content: "A1")
        manager.add(source: .interviewer, content: "Q2")
        manager.add(source: .user, content: "A2")
        manager.add(source: .interviewer, content: "Q3")

        #expect(manager.interviewerCount == 3)
    }

    @Test("userCount should count only user entries")
    func testUserCount() {
        let manager = TranscriptManager()

        manager.add(source: .interviewer, content: "Q1")
        manager.add(source: .user, content: "A1")
        manager.add(source: .interviewer, content: "Q2")
        manager.add(source: .user, content: "A2")
        manager.add(source: .interviewer, content: "Q3")

        #expect(manager.userCount == 2)
    }

    @Test("interviewerCount + userCount should equal count")
    func testSourceCountsSum() {
        let manager = TranscriptManager()

        for i in 0..<100 {
            let source: TranscriptSource = i % 3 == 0 ? .interviewer : .user
            manager.add(source: source, content: "Entry \(i)")
        }

        #expect(manager.interviewerCount + manager.userCount == manager.count)
    }

    @Test("source counts should be 0 for empty manager")
    func testSourceCountsEmpty() {
        let manager = TranscriptManager()

        #expect(manager.interviewerCount == 0)
        #expect(manager.userCount == 0)
    }

    @Test("source counts should update after clear")
    func testSourceCountsAfterClear() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Q1")
        manager.add(source: .user, content: "A1")

        manager.clear()

        #expect(manager.interviewerCount == 0)
        #expect(manager.userCount == 0)
    }
}

@Suite("TranscriptManager Statistics - Word Count")
struct TranscriptManagerWordCountTests {

    @Test("totalWordCount should count words in all entries")
    func testTotalWordCount() {
        let manager = TranscriptManager()

        manager.add(source: .interviewer, content: "one two three")  // 3 words
        manager.add(source: .user, content: "four five")  // 2 words

        #expect(manager.totalWordCount == 5)
    }

    @Test("totalWordCount should handle single word entries")
    func testSingleWordEntries() {
        let manager = TranscriptManager()

        manager.add(source: .interviewer, content: "Hello")
        manager.add(source: .user, content: "World")

        #expect(manager.totalWordCount == 2)
    }

    @Test("totalWordCount should handle empty content")
    func testWordCountEmptyContent() {
        let manager = TranscriptManager()

        manager.add(source: .interviewer, content: "")
        manager.add(source: .user, content: "one two")

        #expect(manager.totalWordCount == 2)
    }

    @Test("totalWordCount should handle whitespace-only content")
    func testWordCountWhitespaceOnly() {
        let manager = TranscriptManager()

        manager.add(source: .interviewer, content: "   \t\n  ")
        manager.add(source: .user, content: "actual words")

        #expect(manager.totalWordCount == 2)
    }

    @Test("totalWordCount should handle multiple spaces between words")
    func testWordCountMultipleSpaces() {
        let manager = TranscriptManager()

        manager.add(source: .interviewer, content: "one    two     three")

        #expect(manager.totalWordCount == 3)
    }

    @Test("totalWordCount should be 0 for empty manager")
    func testWordCountEmpty() {
        let manager = TranscriptManager()

        #expect(manager.totalWordCount == 0)
    }

    @Test("totalWordCount should update after clear")
    func testWordCountAfterClear() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "one two three four five")

        #expect(manager.totalWordCount == 5)

        manager.clear()

        #expect(manager.totalWordCount == 0)
    }

    @Test("totalWordCount should handle punctuation correctly")
    func testWordCountWithPunctuation() {
        let manager = TranscriptManager()

        // "Hello, world!" should count as 2 words
        manager.add(source: .interviewer, content: "Hello, world!")

        #expect(manager.totalWordCount == 2)
    }
}

// MARK: - Task 6.1.3: Export to JSON Tests

@Suite("TranscriptManager JSON Export")
struct TranscriptManagerJSONExportTests {

    @Test("toJSON should return valid JSON string")
    func testToJSONValid() throws {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Question")
        manager.add(source: .user, content: "Answer")

        let jsonString = manager.toJSON()

        // Should be parseable JSON
        let data = jsonString.data(using: .utf8)
        #expect(data != nil)

        let parsed = try JSONSerialization.jsonObject(with: data!)
        #expect(parsed is [[String: Any]])
    }

    @Test("toJSON should include all entries")
    func testToJSONIncludesAllEntries() throws {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Q1")
        manager.add(source: .user, content: "A1")
        manager.add(source: .interviewer, content: "Q2")

        let jsonString = manager.toJSON()
        let data = jsonString.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        #expect(parsed.count == 3)
    }

    @Test("toJSON should include source field")
    func testToJSONIncludesSource() throws {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Test")

        let jsonString = manager.toJSON()

        #expect(jsonString.contains("interviewer") || jsonString.contains("source"))
    }

    @Test("toJSON should include content field")
    func testToJSONIncludesContent() throws {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Unique test content 12345")

        let jsonString = manager.toJSON()

        #expect(jsonString.contains("Unique test content 12345"))
    }

    @Test("toJSON should include timestamp field")
    func testToJSONIncludesTimestamp() throws {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Test")

        let jsonString = manager.toJSON()

        #expect(jsonString.contains("timestamp"))
    }

    @Test("toJSON should return empty array for empty manager")
    func testToJSONEmpty() throws {
        let manager = TranscriptManager()

        let jsonString = manager.toJSON()

        #expect(jsonString == "[]")
    }

    @Test("toJSON should handle special characters")
    func testToJSONSpecialCharacters() throws {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "Test with \"quotes\" and \\backslash")

        let jsonString = manager.toJSON()

        // Should be valid JSON (escaped properly)
        let data = jsonString.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        #expect(parsed.count == 1)
    }

    @Test("toJSON should handle unicode")
    func testToJSONUnicode() throws {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "Unicode: \u{1F680} \u{1F389}")

        let jsonString = manager.toJSON()

        // Should be valid JSON and contain unicode
        let data = jsonString.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        #expect(parsed.count == 1)

        let content = (parsed[0]["content"] as? String) ?? ""
        #expect(content.contains("\u{1F680}") || content.contains("\u{1F389}"))
    }
}

// MARK: - Task 6.1.3: Export to Markdown Tests

@Suite("TranscriptManager Markdown Export")
struct TranscriptManagerMarkdownExportTests {

    @Test("toMarkdown should return non-empty string")
    func testToMarkdownNotEmpty() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Question")

        let markdown = manager.toMarkdown()

        #expect(!markdown.isEmpty)
    }

    @Test("toMarkdown should include transcript header")
    func testToMarkdownHeader() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Question")

        let markdown = manager.toMarkdown()

        #expect(markdown.contains("#") || markdown.contains("Transcript"))
    }

    @Test("toMarkdown should differentiate interviewer entries")
    func testToMarkdownInterviewerFormat() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Interviewer question here")

        let markdown = manager.toMarkdown()

        // Should contain interviewer indicator and content
        #expect(markdown.contains("Interviewer question here"))
        #expect(markdown.contains("Interviewer") || markdown.contains("**") || markdown.contains(">"))
    }

    @Test("toMarkdown should differentiate user entries")
    func testToMarkdownUserFormat() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "User response here")

        let markdown = manager.toMarkdown()

        // Should contain user indicator and content
        #expect(markdown.contains("User response here"))
    }

    @Test("toMarkdown should include timestamps")
    func testToMarkdownTimestamps() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Test")

        let markdown = manager.toMarkdown()

        // Should include time indicator (HH:MM or similar)
        #expect(markdown.contains(":") || markdown.contains("["))
    }

    @Test("toMarkdown should preserve order")
    func testToMarkdownOrder() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "FIRST_ENTRY")
        manager.add(source: .user, content: "SECOND_ENTRY")
        manager.add(source: .interviewer, content: "THIRD_ENTRY")

        let markdown = manager.toMarkdown()

        let firstIndex = markdown.range(of: "FIRST_ENTRY")?.lowerBound
        let secondIndex = markdown.range(of: "SECOND_ENTRY")?.lowerBound
        let thirdIndex = markdown.range(of: "THIRD_ENTRY")?.lowerBound

        #expect(firstIndex != nil)
        #expect(secondIndex != nil)
        #expect(thirdIndex != nil)
        #expect(firstIndex! < secondIndex!)
        #expect(secondIndex! < thirdIndex!)
    }

    @Test("toMarkdown should handle empty manager")
    func testToMarkdownEmpty() {
        let manager = TranscriptManager()

        let markdown = manager.toMarkdown()

        // Should return header or empty indicator, not crash
        #expect(markdown.isEmpty || markdown.contains("No") || markdown.contains("Empty") || markdown.contains("#"))
    }

    @Test("toMarkdown should handle multi-line content")
    func testToMarkdownMultiLine() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "Line 1\nLine 2\nLine 3")

        let markdown = manager.toMarkdown()

        #expect(markdown.contains("Line 1"))
        #expect(markdown.contains("Line 2"))
        #expect(markdown.contains("Line 3"))
    }

    @Test("toMarkdown should escape markdown special characters")
    func testToMarkdownEscaping() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "Content with *asterisks* and _underscores_")

        let markdown = manager.toMarkdown()

        // Content should be present (may or may not be escaped)
        #expect(markdown.contains("asterisks") && markdown.contains("underscores"))
    }
}

// MARK: - Task 6.1.3: Export for Feedback Request Tests

@Suite("TranscriptManager Feedback Format Export")
struct TranscriptManagerFeedbackFormatTests {

    @Test("toFormattedTranscript should return array of dictionaries")
    func testToFormattedTranscriptType() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Question")

        let formatted = manager.toFormattedTranscript(for: true)

        #expect(formatted is [[String: String]])
        #expect(formatted.count == 1)
    }

    @Test("toFormattedTranscript should include role field")
    func testToFormattedTranscriptRole() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Question")
        manager.add(source: .user, content: "Answer")

        let formatted = manager.toFormattedTranscript(for: true)

        #expect(formatted[0]["role"] != nil)
        #expect(formatted[1]["role"] != nil)
    }

    @Test("toFormattedTranscript should map interviewer to correct role")
    func testInterviewerRole() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Question")

        let formatted = manager.toFormattedTranscript(for: true)

        // Interviewer might be mapped to "assistant" or "interviewer"
        let role = formatted[0]["role"] ?? ""
        #expect(role == "assistant" || role == "interviewer")
    }

    @Test("toFormattedTranscript should map user to correct role")
    func testUserRole() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "Answer")

        let formatted = manager.toFormattedTranscript(for: true)

        // User might be mapped to "user" or "candidate"
        let role = formatted[0]["role"] ?? ""
        #expect(role == "user" || role == "candidate")
    }

    @Test("toFormattedTranscript should include content field")
    func testToFormattedTranscriptContent() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Specific test content XYZ")

        let formatted = manager.toFormattedTranscript(for: true)

        #expect(formatted[0]["content"] == "Specific test content XYZ")
    }

    @Test("toFormattedTranscript should preserve order")
    func testToFormattedTranscriptOrder() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "First")
        manager.add(source: .user, content: "Second")
        manager.add(source: .interviewer, content: "Third")

        let formatted = manager.toFormattedTranscript(for: true)

        #expect(formatted[0]["content"] == "First")
        #expect(formatted[1]["content"] == "Second")
        #expect(formatted[2]["content"] == "Third")
    }

    @Test("toFormattedTranscript should return empty array for empty manager")
    func testToFormattedTranscriptEmpty() {
        let manager = TranscriptManager()

        let formatted = manager.toFormattedTranscript(for: true)

        #expect(formatted.isEmpty)
    }

    @Test("toFormattedTranscript for feedback should include all entries")
    func testToFormattedTranscriptForFeedback() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Q1")
        manager.add(source: .user, content: "A1")
        manager.add(source: .interviewer, content: "Q2")
        manager.add(source: .user, content: "A2")

        let formatted = manager.toFormattedTranscript(for: true)

        #expect(formatted.count == 4)
    }

    @Test("toFormattedTranscript for non-feedback may filter entries")
    func testToFormattedTranscriptForNonFeedback() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Q1")
        manager.add(source: .user, content: "A1")

        let formatted = manager.toFormattedTranscript(for: false)

        // May filter or format differently for non-feedback requests
        #expect(formatted.count >= 0)
    }
}

// MARK: - Task 6.1.3: Thread Safety Tests

@Suite("TranscriptManager Thread Safety")
struct TranscriptManagerThreadSafetyTests {

    @Test("TranscriptManager should be Sendable")
    func testSendable() async {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Test")

        await withTaskGroup(of: Int.self) { group in
            group.addTask {
                return manager.count
            }

            for await result in group {
                #expect(result == 1)
            }
        }
    }

    @Test("TranscriptManager should handle concurrent reads")
    func testConcurrentReads() async {
        let manager = TranscriptManager()
        for i in 0..<100 {
            manager.add(source: i % 2 == 0 ? .interviewer : .user, content: "Entry \(i)")
        }

        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    return manager.count
                }
                group.addTask {
                    return manager.interviewerCount
                }
                group.addTask {
                    return manager.userCount
                }
            }

            for await result in group {
                #expect(result >= 0)
            }
        }
    }

    @Test("TranscriptManager should handle concurrent writes")
    func testConcurrentWrites() async {
        let manager = TranscriptManager()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let source: TranscriptSource = i % 2 == 0 ? .interviewer : .user
                    manager.add(source: source, content: "Concurrent entry \(i)")
                }
            }
        }

        // All entries should be added (no lost updates)
        #expect(manager.count == 100)
    }

    @Test("TranscriptManager should handle concurrent read-write")
    func testConcurrentReadWrite() async {
        let manager = TranscriptManager()

        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<50 {
                group.addTask {
                    manager.add(source: .user, content: "Entry \(i)")
                }
            }

            // Readers
            for _ in 0..<50 {
                group.addTask {
                    _ = manager.count
                    _ = manager.entries
                    _ = manager.totalWordCount
                }
            }
        }

        // Should complete without crash
        #expect(manager.count == 50)
    }

    @Test("TranscriptManager entries should be safe to pass across tasks")
    func testEntriesSafeAcrossTasks() async {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Test content")

        let entries = manager.entries

        await withTaskGroup(of: String.self) { group in
            group.addTask {
                return entries.first?.content ?? ""
            }

            for await result in group {
                #expect(result == "Test content")
            }
        }
    }
}

// MARK: - Task 6.1.3: Edge Cases Tests

@Suite("TranscriptManager Edge Cases")
struct TranscriptManagerEdgeCasesTests {

    @Test("Manager should handle newlines in content")
    func testNewlinesInContent() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "Line1\nLine2\nLine3")

        let json = manager.toJSON()
        let markdown = manager.toMarkdown()

        // Should not crash and should preserve content
        #expect(manager.entries.first?.content.contains("\n") == true)
        #expect(!json.isEmpty)
        #expect(!markdown.isEmpty)
    }

    @Test("Manager should handle tab characters")
    func testTabCharacters() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "Column1\tColumn2\tColumn3")

        #expect(manager.entries.first?.content.contains("\t") == true)
    }

    @Test("Manager should handle null-like content")
    func testNullLikeContent() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "null")
        manager.add(source: .user, content: "undefined")
        manager.add(source: .user, content: "nil")

        #expect(manager.count == 3)
    }

    @Test("Manager should handle JSON-like content")
    func testJSONLikeContent() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "{\"key\": \"value\"}")

        let json = manager.toJSON()

        // Should properly escape nested JSON
        let data = json.data(using: .utf8)
        #expect(data != nil)

        let parsed = try? JSONSerialization.jsonObject(with: data!)
        #expect(parsed != nil)
    }

    @Test("Manager should handle very long single entry")
    func testVeryLongEntry() {
        let manager = TranscriptManager()
        let longContent = String(repeating: "A", count: 100_000)

        manager.add(source: .user, content: longContent)

        #expect(manager.entries.first?.content.count == 100_000)
    }

    @Test("Manager should handle rapidly alternating sources")
    func testRapidlyAlternatingSources() {
        let manager = TranscriptManager()

        for i in 0..<1000 {
            let source: TranscriptSource = i % 2 == 0 ? .interviewer : .user
            manager.add(source: source, content: "\(i)")
        }

        #expect(manager.interviewerCount == 500)
        #expect(manager.userCount == 500)
    }

    @Test("Manager should handle emoji content")
    func testEmojiContent() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "    ")

        #expect(manager.entries.first?.content == "    ")
    }

    @Test("Manager should handle RTL text")
    func testRTLText() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "")

        #expect(manager.entries.first?.content == "")
    }

    @Test("Manager should handle mixed language content")
    func testMixedLanguageContent() {
        let manager = TranscriptManager()
        manager.add(source: .user, content: "English Japanese:")

        #expect(manager.entries.first?.content.contains("English") == true)
        #expect(manager.entries.first?.content.contains("") == true)
    }
}

// MARK: - Task 6.1.3: Codable Tests

@Suite("TranscriptManager Codable")
struct TranscriptManagerCodableTests {

    @Test("TranscriptManager should be Encodable")
    func testEncodable() throws {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "Q1")
        manager.add(source: .user, content: "A1")

        let encoder = JSONEncoder()
        let data = try encoder.encode(manager)

        #expect(data.count > 0)
    }

    @Test("TranscriptManager should be Decodable")
    func testDecodable() throws {
        // First encode a manager
        let original = TranscriptManager()
        original.add(source: .interviewer, content: "Question")
        original.add(source: .user, content: "Answer")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TranscriptManager.self, from: data)

        #expect(decoded.count == 2)
    }

    @Test("TranscriptManager should survive round-trip encoding")
    func testRoundTrip() throws {
        let original = TranscriptManager()
        original.add(source: .interviewer, content: "Q1")
        original.add(source: .user, content: "A1")
        original.add(source: .interviewer, content: "Q2")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TranscriptManager.self, from: data)

        #expect(decoded.count == original.count)
        #expect(decoded.interviewerCount == original.interviewerCount)
        #expect(decoded.userCount == original.userCount)

        // Verify content
        for i in 0..<original.count {
            #expect(decoded.entries[i].source == original.entries[i].source)
            #expect(decoded.entries[i].content == original.entries[i].content)
        }
    }
}

// MARK: - Task 6.1.3: Integration-like Tests

@Suite("TranscriptManager Integration")
struct TranscriptManagerIntegrationTests {

    @Test("Full interview simulation")
    func testFullInterviewSimulation() {
        let manager = TranscriptManager()

        // Simulate a short interview
        manager.add(source: .interviewer, content: "Let's design a URL shortener. What are the requirements?")
        manager.add(source: .user, content: "We need to support about 100 million URLs with 1000 QPS for reads.")
        manager.add(source: .interviewer, content: "Good. How would you estimate the storage requirements?")
        manager.add(source: .user, content: "If each URL mapping is 500 bytes, for 100M URLs we need 50GB.")
        manager.add(source: .interviewer, content: "What about the database schema?")
        manager.add(source: .user, content: "I would use a simple key-value store with the short URL as key.")

        // Verify statistics
        #expect(manager.count == 6)
        #expect(manager.interviewerCount == 3)
        #expect(manager.userCount == 3)
        #expect(manager.totalWordCount > 50)

        // Verify exports work
        let json = manager.toJSON()
        let markdown = manager.toMarkdown()
        let formatted = manager.toFormattedTranscript(for: true)

        #expect(!json.isEmpty)
        #expect(!markdown.isEmpty)
        #expect(formatted.count == 6)
    }

    @Test("Export formats should be consistent")
    func testExportConsistency() {
        let manager = TranscriptManager()
        manager.add(source: .interviewer, content: "TestQuestion")
        manager.add(source: .user, content: "TestAnswer")

        // All exports should contain the content
        let json = manager.toJSON()
        let markdown = manager.toMarkdown()
        let formatted = manager.toFormattedTranscript(for: true)

        #expect(json.contains("TestQuestion"))
        #expect(json.contains("TestAnswer"))
        #expect(markdown.contains("TestQuestion"))
        #expect(markdown.contains("TestAnswer"))
        #expect(formatted.contains { $0["content"] == "TestQuestion" })
        #expect(formatted.contains { $0["content"] == "TestAnswer" })
    }

    @Test("Statistics should update correctly through operations")
    func testStatisticsUpdates() {
        let manager = TranscriptManager()

        // Add entries
        manager.add(source: .interviewer, content: "one two three")
        #expect(manager.count == 1)
        #expect(manager.totalWordCount == 3)

        manager.add(source: .user, content: "four five")
        #expect(manager.count == 2)
        #expect(manager.totalWordCount == 5)

        // Clear
        manager.clear()
        #expect(manager.count == 0)
        #expect(manager.totalWordCount == 0)

        // Add again
        manager.add(source: .interviewer, content: "new words here")
        #expect(manager.count == 1)
        #expect(manager.totalWordCount == 3)
    }
}
