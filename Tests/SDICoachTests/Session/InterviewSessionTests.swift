// InterviewSessionTests.swift
// TDD RED Phase: Failing tests for InterviewSession state management
//
// Task 6.1.1: InterviewSession state management
//
// Type definitions from PRD.md:
// - InterviewSession: question, startTime, transcripts, followUpCount, isPaused, remainingSeconds
// - TranscriptEntry: timestamp, source, content (already exists in TUIEngine.swift)
// - TranscriptSource: .interviewer, .user (already exists in TUIEngine.swift)
//
// Test framework: swift-testing (NOT XCTest)
// Feature: sdi.coach Session Management
//
// NOTE: TranscriptSource and TranscriptEntry already exist in Sources/SDICoach/TUI/TUIEngine.swift
// This test file focuses on the NEW InterviewSession type which does NOT exist yet.

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 6.1.1: TranscriptSource Enum Tests (Existing Type - Verify Behavior)

@Suite("TranscriptSource Enum Definition")
struct TranscriptSourceDefinitionTests {

    @Test("TranscriptSource has both interviewer and user cases")
    func testBasicCases() {
        // Verify both cases exist and are distinct
        let interviewer: TranscriptSource = .interviewer
        let user: TranscriptSource = .user
        #expect(interviewer != user)
        #expect(interviewer == .interviewer)
        #expect(user == .user)
    }

    @Test("TranscriptSource should be Sendable")
    func testSendable() async {
        let source: TranscriptSource = .interviewer

        await withTaskGroup(of: TranscriptSource.self) { group in
            group.addTask {
                return source
            }

            for await result in group {
                #expect(result == .interviewer)
            }
        }
    }

    @Test("TranscriptSource should be Codable")
    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Encode and decode interviewer
        let interviewerData = try encoder.encode(TranscriptSource.interviewer)
        let decodedInterviewer = try decoder.decode(TranscriptSource.self, from: interviewerData)
        #expect(decodedInterviewer == .interviewer)

        // Encode and decode user
        let userData = try encoder.encode(TranscriptSource.user)
        let decodedUser = try decoder.decode(TranscriptSource.self, from: userData)
        #expect(decodedUser == .user)
    }
}

// MARK: - Task 6.1.1: TranscriptEntry Struct Tests (Existing Type - Verify Behavior)

@Suite("TranscriptEntry Struct Definition")
struct TranscriptEntryDefinitionTests {

    @Test("TranscriptEntry should be initializable with all properties")
    func testInitialization() {
        let timestamp = Date()
        let source: TranscriptSource = .interviewer
        let content = "What are the requirements for this system?"

        // Note: Existing initializer order is (source:content:timestamp:)
        let entry = TranscriptEntry(
            source: source,
            content: content,
            timestamp: timestamp
        )

        #expect(entry.timestamp == timestamp)
        #expect(entry.source == source)
        #expect(entry.content == content)
    }

    @Test("TranscriptEntry should store interviewer source correctly")
    func testInterviewerSource() {
        let entry = TranscriptEntry(
            source: .interviewer,
            content: "Hello",
            timestamp: Date()
        )
        #expect(entry.source == .interviewer)
    }

    @Test("TranscriptEntry should store user source correctly")
    func testUserSource() {
        let entry = TranscriptEntry(
            source: .user,
            content: "Hello",
            timestamp: Date()
        )
        #expect(entry.source == .user)
    }

    @Test("TranscriptEntry should preserve empty content")
    func testEmptyContent() {
        let entry = TranscriptEntry(
            source: .user,
            content: "",
            timestamp: Date()
        )
        #expect(entry.content == "")
    }

    @Test("TranscriptEntry should preserve content with special characters")
    func testSpecialCharacters() {
        let specialContent = "Design @#$%^&*() system with unicode: "
        let entry = TranscriptEntry(
            source: .user,
            content: specialContent,
            timestamp: Date()
        )
        #expect(entry.content == specialContent)
    }

    @Test("TranscriptEntry should preserve content with newlines")
    func testNewlinesInContent() {
        let multilineContent = "Line 1\nLine 2\nLine 3"
        let entry = TranscriptEntry(
            source: .interviewer,
            content: multilineContent,
            timestamp: Date()
        )
        #expect(entry.content == multilineContent)
    }

    @Test("TranscriptEntry should preserve very long content")
    func testLongContent() {
        let longContent = String(repeating: "Design ", count: 1000)
        let entry = TranscriptEntry(
            source: .user,
            content: longContent,
            timestamp: Date()
        )
        #expect(entry.content == longContent)
    }
}

@Suite("TranscriptEntry Codable")
struct TranscriptEntryCodableTests {

    @Test("TranscriptEntry should encode to JSON")
    func testEncoding() throws {
        let timestamp = Date(timeIntervalSince1970: 1707350400) // Fixed timestamp for testing
        let entry = TranscriptEntry(
            source: .interviewer,
            content: "Test question",
            timestamp: timestamp
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        let jsonString = String(data: data, encoding: .utf8)

        #expect(jsonString != nil)
        #expect(jsonString!.contains("Test question"))
    }

    @Test("TranscriptEntry should decode from JSON")
    func testDecoding() throws {
        let json = """
        {
            "timestamp": 1707350400,
            "source": "interviewer",
            "content": "What are the requirements?"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let entry = try decoder.decode(TranscriptEntry.self, from: json.data(using: .utf8)!)

        #expect(entry.source == .interviewer)
        #expect(entry.content == "What are the requirements?")
    }

    @Test("TranscriptEntry should survive round-trip encoding")
    func testRoundTrip() throws {
        let original = TranscriptEntry(
            source: .user,
            content: "I think we need to support around 100 million URLs",
            timestamp: Date()
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(TranscriptEntry.self, from: encoded)

        #expect(decoded.source == original.source)
        #expect(decoded.content == original.content)
        // Note: Date comparison might have small precision differences
    }
}

// MARK: - Task 6.1.1: InterviewSession Struct Tests (NEW TYPE - WILL FAIL)
//
// The following tests are for the InterviewSession type defined in PRD.md
// This type does NOT exist yet and these tests MUST FAIL until implementation.
//
// Expected struct definition:
// struct InterviewSession {
//     let question: String
//     let startTime: Date
//     var transcripts: [TranscriptEntry]
//     var followUpCount: Int           // Track follow-ups per topic
//     var isPaused: Bool
//     var remainingSeconds: Int        // 30 * 60 = 1800
// }

@Suite("InterviewSession Initialization")
struct InterviewSessionInitializationTests {

    @Test("InterviewSession should initialize with correct defaults")
    func testInitializationWithDefaults() {
        let question = "Design a URL shortener service"
        let beforeInit = Date()

        let session = InterviewSession(question: question)

        let afterInit = Date()

        // Verify question
        #expect(session.question == question)
        // Verify startTime is between beforeInit and afterInit
        #expect(session.startTime >= beforeInit)
        #expect(session.startTime <= afterInit)
        // Verify all default values
        #expect(session.transcripts.isEmpty)
        #expect(session.followUpCount == 0)
        #expect(session.isPaused == false)
        #expect(session.remainingSeconds == 1800)
    }

    @Test("InterviewSession should preserve question with special characters")
    func testQuestionWithSpecialCharacters() {
        let specialQuestion = "Design @#$% system with unicode: "
        let session = InterviewSession(question: specialQuestion)
        #expect(session.question == specialQuestion)
    }

    @Test("InterviewSession should preserve empty question")
    func testEmptyQuestion() {
        let session = InterviewSession(question: "")
        #expect(session.question == "")
    }

    @Test("InterviewSession should preserve very long question")
    func testLongQuestion() {
        let longQuestion = String(repeating: "Design ", count: 1000)
        let session = InterviewSession(question: longQuestion)
        #expect(session.question == longQuestion)
    }
}

// MARK: - TranscriptEntry Addition Tests

@Suite("InterviewSession Transcript Management")
struct InterviewSessionTranscriptTests {

    @Test("addTranscript should add entry to transcripts array")
    func testAddTranscript() {
        var session = InterviewSession(question: "Design a cache")
        #expect(session.transcripts.count == 0)

        session.addTranscript(source: .interviewer, content: "What are the requirements?")

        #expect(session.transcripts.count == 1)
    }

    @Test("addTranscript should store correct source")
    func testAddTranscriptSource() {
        var session = InterviewSession(question: "Design a cache")

        session.addTranscript(source: .interviewer, content: "Question")
        session.addTranscript(source: .user, content: "Answer")

        #expect(session.transcripts[0].source == .interviewer)
        #expect(session.transcripts[1].source == .user)
    }

    @Test("addTranscript should store correct content")
    func testAddTranscriptContent() {
        var session = InterviewSession(question: "Design a cache")
        let content = "I think we need to support around 100 million URLs"

        session.addTranscript(source: .user, content: content)

        #expect(session.transcripts[0].content == content)
    }

    @Test("addTranscript should automatically record timestamp")
    func testAddTranscriptTimestamp() {
        var session = InterviewSession(question: "Design a cache")
        let beforeAdd = Date()

        session.addTranscript(source: .user, content: "Answer")

        let afterAdd = Date()

        #expect(session.transcripts[0].timestamp >= beforeAdd)
        #expect(session.transcripts[0].timestamp <= afterAdd)
    }

    @Test("addTranscript should preserve order of entries")
    func testAddTranscriptOrder() {
        var session = InterviewSession(question: "Design a cache")

        session.addTranscript(source: .interviewer, content: "First")
        session.addTranscript(source: .user, content: "Second")
        session.addTranscript(source: .interviewer, content: "Third")

        #expect(session.transcripts[0].content == "First")
        #expect(session.transcripts[1].content == "Second")
        #expect(session.transcripts[2].content == "Third")
    }

    @Test("addTranscript should handle empty content")
    func testAddTranscriptEmptyContent() {
        var session = InterviewSession(question: "Design a cache")

        session.addTranscript(source: .user, content: "")

        #expect(session.transcripts.count == 1)
        #expect(session.transcripts[0].content == "")
    }

    @Test("addTranscript should handle special characters in content")
    func testAddTranscriptSpecialCharacters() {
        var session = InterviewSession(question: "Design a cache")
        let specialContent = "Answer with unicode:  and symbols: @#$%"

        session.addTranscript(source: .user, content: specialContent)

        #expect(session.transcripts[0].content == specialContent)
    }

    @Test("addTranscript should handle multiple entries")
    func testAddMultipleTranscripts() {
        var session = InterviewSession(question: "Design a cache")

        for i in 0..<100 {
            let source: TranscriptSource = i % 2 == 0 ? .interviewer : .user
            session.addTranscript(source: source, content: "Entry \(i)")
        }

        #expect(session.transcripts.count == 100)
    }
}

// MARK: - Pause/Resume Tests

@Suite("InterviewSession Pause/Resume")
struct InterviewSessionPauseResumeTests {

    @Test("pause should set isPaused to true")
    func testPause() {
        var session = InterviewSession(question: "Design a cache")
        #expect(session.isPaused == false)

        session.pause()

        #expect(session.isPaused == true)
    }

    @Test("resume should set isPaused to false")
    func testResume() {
        var session = InterviewSession(question: "Design a cache")
        session.pause()
        #expect(session.isPaused == true)

        session.resume()

        #expect(session.isPaused == false)
    }

    @Test("pause when already paused should remain paused")
    func testPauseWhenAlreadyPaused() {
        var session = InterviewSession(question: "Design a cache")
        session.pause()

        session.pause()

        #expect(session.isPaused == true)
    }

    @Test("resume when not paused should remain not paused")
    func testResumeWhenNotPaused() {
        var session = InterviewSession(question: "Design a cache")
        #expect(session.isPaused == false)

        session.resume()

        #expect(session.isPaused == false)
    }

    @Test("multiple pause/resume cycles should work correctly")
    func testMultiplePauseResumeCycles() {
        var session = InterviewSession(question: "Design a cache")

        for _ in 0..<10 {
            session.pause()
            #expect(session.isPaused == true)

            session.resume()
            #expect(session.isPaused == false)
        }
    }

    @Test("pause should not affect other session properties")
    func testPauseDoesNotAffectOtherProperties() {
        var session = InterviewSession(question: "Design a cache")
        let originalQuestion = session.question
        let originalStartTime = session.startTime
        let originalFollowUpCount = session.followUpCount
        let originalRemainingSeconds = session.remainingSeconds

        session.pause()

        #expect(session.question == originalQuestion)
        #expect(session.startTime == originalStartTime)
        #expect(session.followUpCount == originalFollowUpCount)
        #expect(session.remainingSeconds == originalRemainingSeconds)
    }

    @Test("resume should not affect other session properties")
    func testResumeDoesNotAffectOtherProperties() {
        var session = InterviewSession(question: "Design a cache")
        session.pause()
        session.addTranscript(source: .user, content: "Test")
        let transcriptCount = session.transcripts.count

        session.resume()

        #expect(session.transcripts.count == transcriptCount)
    }
}

// MARK: - Follow-up Count Tests

@Suite("InterviewSession Follow-up Count")
struct InterviewSessionFollowUpCountTests {

    @Test("incrementFollowUp should increase followUpCount by 1")
    func testIncrementFollowUp() {
        var session = InterviewSession(question: "Design a cache")
        #expect(session.followUpCount == 0)

        session.incrementFollowUp()

        #expect(session.followUpCount == 1)
    }

    @Test("incrementFollowUp should work multiple times")
    func testMultipleIncrements() {
        var session = InterviewSession(question: "Design a cache")

        session.incrementFollowUp()
        session.incrementFollowUp()
        session.incrementFollowUp()

        #expect(session.followUpCount == 3)
    }

    @Test("resetFollowUp should set followUpCount to 0")
    func testResetFollowUp() {
        var session = InterviewSession(question: "Design a cache")
        session.incrementFollowUp()
        session.incrementFollowUp()
        #expect(session.followUpCount == 2)

        session.resetFollowUp()

        #expect(session.followUpCount == 0)
    }

    @Test("resetFollowUp when already 0 should remain 0")
    func testResetFollowUpWhenZero() {
        var session = InterviewSession(question: "Design a cache")
        #expect(session.followUpCount == 0)

        session.resetFollowUp()

        #expect(session.followUpCount == 0)
    }

    @Test("incrementFollowUp after reset should start from 0")
    func testIncrementAfterReset() {
        var session = InterviewSession(question: "Design a cache")
        session.incrementFollowUp()
        session.incrementFollowUp()
        session.resetFollowUp()

        session.incrementFollowUp()

        #expect(session.followUpCount == 1)
    }

    @Test("followUpCount should handle many increments")
    func testManyIncrements() {
        var session = InterviewSession(question: "Design a cache")

        for _ in 0..<100 {
            session.incrementFollowUp()
        }

        #expect(session.followUpCount == 100)
    }

    @Test("incrementFollowUp should not affect other properties")
    func testIncrementDoesNotAffectOtherProperties() {
        var session = InterviewSession(question: "Design a cache")
        let originalIsPaused = session.isPaused
        let originalRemainingSeconds = session.remainingSeconds

        session.incrementFollowUp()

        #expect(session.isPaused == originalIsPaused)
        #expect(session.remainingSeconds == originalRemainingSeconds)
    }
}

// MARK: - Time Management Tests

@Suite("InterviewSession Time Management")
struct InterviewSessionTimeManagementTests {

    @Test("decrementTime should decrease remainingSeconds")
    func testDecrementTime() {
        var session = InterviewSession(question: "Design a cache")
        #expect(session.remainingSeconds == 1800)

        session.decrementTime(by: 1)

        #expect(session.remainingSeconds == 1799)
    }

    @Test("decrementTime should decrease by specified amount")
    func testDecrementTimeByAmount() {
        var session = InterviewSession(question: "Design a cache")

        session.decrementTime(by: 60)

        #expect(session.remainingSeconds == 1740)
    }

    @Test("decrementTime should not go below 0")
    func testDecrementTimeNotBelowZero() {
        var session = InterviewSession(question: "Design a cache")

        session.decrementTime(by: 2000)

        #expect(session.remainingSeconds == 0)
    }

    @Test("decrementTime with exact remaining should result in 0")
    func testDecrementTimeExactRemaining() {
        var session = InterviewSession(question: "Design a cache")

        session.decrementTime(by: 1800)

        #expect(session.remainingSeconds == 0)
    }

    @Test("decrementTime with 0 should not change remainingSeconds")
    func testDecrementTimeByZero() {
        var session = InterviewSession(question: "Design a cache")

        session.decrementTime(by: 0)

        #expect(session.remainingSeconds == 1800)
    }

    @Test("decrementTime multiple times should accumulate")
    func testDecrementTimeMultipleTimes() {
        var session = InterviewSession(question: "Design a cache")

        session.decrementTime(by: 100)
        session.decrementTime(by: 200)
        session.decrementTime(by: 300)

        #expect(session.remainingSeconds == 1200)
    }

    @Test("decrementTime when already at 0 should remain at 0")
    func testDecrementTimeWhenAtZero() {
        var session = InterviewSession(question: "Design a cache")
        session.decrementTime(by: 1800)
        #expect(session.remainingSeconds == 0)

        session.decrementTime(by: 100)

        #expect(session.remainingSeconds == 0)
    }

    @Test("decrementTime should not affect other properties")
    func testDecrementTimeDoesNotAffectOtherProperties() {
        var session = InterviewSession(question: "Design a cache")
        session.addTranscript(source: .user, content: "Test")
        let originalTranscriptCount = session.transcripts.count
        let originalFollowUpCount = session.followUpCount

        session.decrementTime(by: 60)

        #expect(session.transcripts.count == originalTranscriptCount)
        #expect(session.followUpCount == originalFollowUpCount)
    }

    @Test("remainingSeconds should be in valid range after multiple operations")
    func testRemainingSecondsValidRange() {
        var session = InterviewSession(question: "Design a cache")

        // Decrement beyond zero multiple times
        for _ in 0..<100 {
            session.decrementTime(by: 50)
        }

        // remainingSeconds should always be >= 0
        #expect(session.remainingSeconds >= 0)
    }
}

// MARK: - Time Helpers Tests

@Suite("InterviewSession Time Helpers")
struct InterviewSessionTimeHelpersTests {

    @Test("isTimeUp should return false when time remains")
    func testIsTimeUpFalseWhenTimeRemains() {
        let session = InterviewSession(question: "Design a cache")
        #expect(session.isTimeUp == false)
    }

    @Test("isTimeUp should return true when remainingSeconds is 0")
    func testIsTimeUpTrueWhenZero() {
        var session = InterviewSession(question: "Design a cache")
        session.decrementTime(by: 1800)
        #expect(session.isTimeUp == true)
    }

    @Test("formattedRemainingTime should return MM:SS format")
    func testFormattedRemainingTime() {
        let session = InterviewSession(question: "Design a cache")
        // 1800 seconds = 30:00
        #expect(session.formattedRemainingTime == "30:00")
    }

    @Test("formattedRemainingTime should handle single digit seconds")
    func testFormattedRemainingTimeSingleDigitSeconds() {
        var session = InterviewSession(question: "Design a cache")
        session.decrementTime(by: 1795) // 5 seconds remaining
        #expect(session.formattedRemainingTime == "00:05")
    }

    @Test("formattedRemainingTime should handle single digit minutes")
    func testFormattedRemainingTimeSingleDigitMinutes() {
        var session = InterviewSession(question: "Design a cache")
        session.decrementTime(by: 1200) // 10 minutes remaining (600 seconds)
        #expect(session.formattedRemainingTime == "10:00")
    }

    @Test("formattedRemainingTime should handle zero")
    func testFormattedRemainingTimeZero() {
        var session = InterviewSession(question: "Design a cache")
        session.decrementTime(by: 1800)
        #expect(session.formattedRemainingTime == "00:00")
    }

    @Test("formattedRemainingTime should handle various times")
    func testFormattedRemainingTimeVarious() {
        var session = InterviewSession(question: "Design a cache")

        // 25:35 (25 minutes 35 seconds = 1535 seconds remaining)
        session.decrementTime(by: 265) // 1800 - 265 = 1535
        #expect(session.formattedRemainingTime == "25:35")
    }
}

// MARK: - Codable Tests

@Suite("InterviewSession Codable")
struct InterviewSessionCodableTests {

    @Test("InterviewSession should encode to JSON")
    func testEncoding() throws {
        var session = InterviewSession(question: "Design a cache")
        session.addTranscript(source: .interviewer, content: "Question")
        session.addTranscript(source: .user, content: "Answer")
        session.incrementFollowUp()
        session.decrementTime(by: 60)

        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        let jsonString = String(data: data, encoding: .utf8)

        #expect(jsonString != nil)
        #expect(jsonString!.contains("Design a cache"))
    }

    @Test("InterviewSession should decode from JSON")
    func testDecoding() throws {
        let json = """
        {
            "question": "Design a URL shortener",
            "startTime": 1707350400,
            "transcripts": [],
            "followUpCount": 2,
            "isPaused": true,
            "remainingSeconds": 1500
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let session = try decoder.decode(InterviewSession.self, from: json.data(using: .utf8)!)

        #expect(session.question == "Design a URL shortener")
        #expect(session.followUpCount == 2)
        #expect(session.isPaused == true)
        #expect(session.remainingSeconds == 1500)
    }

    @Test("InterviewSession should survive round-trip encoding")
    func testRoundTrip() throws {
        var original = InterviewSession(question: "Design a cache")
        original.addTranscript(source: .interviewer, content: "Question 1")
        original.addTranscript(source: .user, content: "Answer 1")
        original.incrementFollowUp()
        original.incrementFollowUp()
        original.pause()
        original.decrementTime(by: 300)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(InterviewSession.self, from: encoded)

        #expect(decoded.question == original.question)
        #expect(decoded.transcripts.count == original.transcripts.count)
        #expect(decoded.followUpCount == original.followUpCount)
        #expect(decoded.isPaused == original.isPaused)
        #expect(decoded.remainingSeconds == original.remainingSeconds)
    }

    @Test("InterviewSession with transcripts should survive round-trip")
    func testRoundTripWithTranscripts() throws {
        var original = InterviewSession(question: "Design a cache")
        original.addTranscript(source: .interviewer, content: "What are the requirements?")
        original.addTranscript(source: .user, content: "We need to support 100M URLs")
        original.addTranscript(source: .interviewer, content: "How would you store them?")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(InterviewSession.self, from: encoded)

        #expect(decoded.transcripts.count == 3)
        #expect(decoded.transcripts[0].source == .interviewer)
        #expect(decoded.transcripts[0].content == "What are the requirements?")
        #expect(decoded.transcripts[1].source == .user)
        #expect(decoded.transcripts[2].source == .interviewer)
    }
}

// MARK: - Thread Safety Tests

@Suite("InterviewSession Thread Safety")
struct InterviewSessionThreadSafetyTests {

    @Test("InterviewSession should be Sendable")
    func testSendable() async {
        let session = InterviewSession(question: "Design a cache")

        await withTaskGroup(of: String.self) { group in
            group.addTask {
                return session.question
            }

            for await result in group {
                #expect(result == "Design a cache")
            }
        }
    }

    @Test("TranscriptEntry should be Sendable")
    func testTranscriptEntrySendable() async {
        let entry = TranscriptEntry(
            source: .user,
            content: "Test",
            timestamp: Date()
        )

        await withTaskGroup(of: String.self) { group in
            group.addTask {
                return entry.content
            }

            for await result in group {
                #expect(result == "Test")
            }
        }
    }
}

// MARK: - Edge Cases Tests

@Suite("InterviewSession Edge Cases")
struct InterviewSessionEdgeCasesTests {

    @Test("Session should handle whitespace-only question")
    func testWhitespaceOnlyQuestion() {
        let session = InterviewSession(question: "   \t\n  ")
        #expect(session.question == "   \t\n  ")
    }

    @Test("Session should handle very large followUpCount")
    func testLargeFollowUpCount() {
        var session = InterviewSession(question: "Design a cache")

        for _ in 0..<10000 {
            session.incrementFollowUp()
        }

        #expect(session.followUpCount == 10000)
    }

    @Test("Session should handle rapid state changes")
    func testRapidStateChanges() {
        var session = InterviewSession(question: "Design a cache")

        for i in 0..<100 {
            session.addTranscript(source: i % 2 == 0 ? .interviewer : .user, content: "Entry \(i)")
            session.incrementFollowUp()
            if i % 5 == 0 {
                session.resetFollowUp()
            }
            session.decrementTime(by: 1)
            if i % 3 == 0 {
                session.pause()
            } else {
                session.resume()
            }
        }

        // Session should still be in a valid state
        #expect(session.transcripts.count == 100)
        #expect(session.remainingSeconds == 1700)
    }

    @Test("Session should handle unicode in question and content")
    func testUnicodeContent() {
        var session = InterviewSession(question: "Design a system 🚀")
        session.addTranscript(source: .user, content: "We need to support multiple languages 日本語")
        session.addTranscript(source: .interviewer, content: "How would you handle encoding? 한글")

        #expect(session.question.contains("🚀"))
        #expect(session.transcripts[0].content.contains("日本語"))
        #expect(session.transcripts[1].content.contains("한글"))
    }
}

// MARK: - Computed Properties Tests

@Suite("InterviewSession Computed Properties")
struct InterviewSessionComputedPropertiesTests {

    @Test("elapsedSeconds should return correct value")
    func testElapsedSeconds() {
        var session = InterviewSession(question: "Design a cache")
        session.decrementTime(by: 300)

        #expect(session.elapsedSeconds == 300)
    }

    @Test("elapsedSeconds should be 0 for new session")
    func testElapsedSecondsNew() {
        let session = InterviewSession(question: "Design a cache")
        #expect(session.elapsedSeconds == 0)
    }

    @Test("elapsedSeconds should be 1800 when time is up")
    func testElapsedSecondsTimeUp() {
        var session = InterviewSession(question: "Design a cache")
        session.decrementTime(by: 1800)

        #expect(session.elapsedSeconds == 1800)
    }

    @Test("totalDurationSeconds should be 1800")
    func testTotalDurationSeconds() {
        let session = InterviewSession(question: "Design a cache")
        #expect(session.totalDurationSeconds == 1800)
    }

    @Test("progressPercentage should return correct value")
    func testProgressPercentage() {
        var session = InterviewSession(question: "Design a cache")
        session.decrementTime(by: 900) // Half time elapsed

        // 900/1800 = 0.5 = 50%
        #expect(session.progressPercentage >= 49.9)
        #expect(session.progressPercentage <= 50.1)
    }

    @Test("progressPercentage should be 0 for new session")
    func testProgressPercentageNew() {
        let session = InterviewSession(question: "Design a cache")
        #expect(session.progressPercentage == 0.0)
    }

    @Test("progressPercentage should be 100 when time is up")
    func testProgressPercentageTimeUp() {
        var session = InterviewSession(question: "Design a cache")
        session.decrementTime(by: 1800)

        #expect(session.progressPercentage == 100.0)
    }
}
