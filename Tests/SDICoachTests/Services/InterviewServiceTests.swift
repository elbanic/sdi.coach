// InterviewServiceTests.swift
// TDD RED Phase: Failing tests for InterviewService
//
// Tasks covered:
// - 6.2.1: Interview lifecycle (start, pause, resume, end)
// - 6.2.2: IPC message coordination
// - 6.2.3: Feedback request and markdown saving
//
// InterviewService manages the interview session lifecycle via IPC.
// It coordinates with the Python backend for AI-powered interview functionality.
//
// Test framework: swift-testing (NOT XCTest)
// Feature: sdi.coach Interview Service

import Testing
import Foundation
@testable import SDICoach

// MARK: - Mock Types

/// Mock IPC Client for testing InterviewService
/// Thread-safe implementation using NSLock for synchronization
final class MockInterviewIPCClient: IPCClientProtocol, @unchecked Sendable {
    private var _sentMessages: [IPCMessage] = []
    private var _simulateConnected: Bool = false
    private var _simulatedResponses: [MessageType: IPCMessage] = [:]
    private var _shouldThrowOnSend: Bool = false
    private var _messageHandler: ((IPCMessage) async -> IPCMessage?)?
    private let lock = NSLock()

    var sentMessages: [IPCMessage] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _sentMessages
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _sentMessages = newValue
        }
    }

    var simulateConnected: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _simulateConnected
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _simulateConnected = newValue
        }
    }

    var shouldThrowOnSend: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _shouldThrowOnSend
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _shouldThrowOnSend = newValue
        }
    }

    func setSimulatedResponse(for type: MessageType, response: IPCMessage) {
        lock.lock()
        defer { lock.unlock() }
        _simulatedResponses[type] = response
    }

    func setMessageHandler(_ handler: @escaping (IPCMessage) async -> IPCMessage?) {
        lock.lock()
        defer { lock.unlock() }
        _messageHandler = handler
    }

    func send(_ message: IPCMessage) async throws {
        lock.lock()
        if _shouldThrowOnSend {
            lock.unlock()
            throw IPCError.connectionFailed("Simulated send failure")
        }
        _sentMessages.append(message)
        lock.unlock()
    }

    func isConnected() async -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _simulateConnected
    }

    func sendAndWait(_ message: IPCMessage, timeout: TimeInterval) async throws -> IPCMessage {
        lock.lock()
        if _shouldThrowOnSend {
            lock.unlock()
            throw IPCError.connectionFailed("Simulated send failure")
        }
        _sentMessages.append(message)

        // Check for handler
        if let handler = _messageHandler {
            lock.unlock()
            if let response = await handler(message) {
                return response
            }
            throw IPCError.timeout(timeout)
        }

        // Check for simulated response
        if let response = _simulatedResponses[message.type] {
            lock.unlock()
            return response
        }
        lock.unlock()
        throw IPCError.timeout(timeout)
    }
}

/// Mock TTS Engine for testing InterviewService
final class MockInterviewTTSEngine: TTSEngineProtocol, @unchecked Sendable {
    private var _spokenTexts: [String] = []
    private var _wasStopped: Bool = false
    private var _wasInterrupted: Bool = false
    private let lock = NSLock()

    var spokenTexts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _spokenTexts
    }

    var wasStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _wasStopped
    }

    var wasInterrupted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _wasInterrupted
    }

    func speak(text: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        _spokenTexts.append(text)
    }

    func stop() async throws {
        lock.lock()
        defer { lock.unlock() }
        _wasStopped = true
    }

    func interrupt() async {
        lock.lock()
        defer { lock.unlock() }
        _wasInterrupted = true
    }
}

/// Mock delegate for InterviewService
final class MockInterviewServiceDelegate: InterviewServiceDelegate, @unchecked Sendable {
    private var _receivedQuestions: [String] = []
    private var _receivedFollowUps: [String] = []
    private var _receivedTranscriptions: [(text: String, isFinal: Bool)] = []
    private var _receivedFeedback: [String] = []
    private var _didComplete: Bool = false
    private let lock = NSLock()

    var receivedQuestions: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedQuestions
    }

    var receivedFollowUps: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedFollowUps
    }

    var receivedTranscriptions: [(text: String, isFinal: Bool)] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedTranscriptions
    }

    var receivedFeedback: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedFeedback
    }

    var didComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _didComplete
    }

    public func interviewService(_ service: InterviewService, didReceiveQuestion question: String) async {
        lock.lock()
        defer { lock.unlock() }
        _receivedQuestions.append(question)
    }

    public func interviewService(_ service: InterviewService, didReceiveFollowUp question: String) async {
        lock.lock()
        defer { lock.unlock() }
        _receivedFollowUps.append(question)
    }

    public func interviewService(_ service: InterviewService, didUpdateTranscription text: String, isFinal: Bool) async {
        lock.lock()
        defer { lock.unlock() }
        _receivedTranscriptions.append((text: text, isFinal: isFinal))
    }

    public func interviewService(_ service: InterviewService, didReceiveFeedback markdown: String) async {
        lock.lock()
        defer { lock.unlock() }
        _receivedFeedback.append(markdown)
    }

    public func interviewServiceDidComplete(_ service: InterviewService) async {
        lock.lock()
        defer { lock.unlock() }
        _didComplete = true
    }

    public func interviewService(_ service: InterviewService, didReceiveError error: String, message: String) async {
        // Mock implementation - can be extended to track errors if needed
    }
}

// MARK: - Task 6.2.1: Initialization Tests

@Suite("InterviewService Initialization")
struct InterviewServiceInitializationTests {

    @Test("InterviewService should be initializable with IPC client")
    func testInitializationWithIPCClient() async {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        // Service should exist and be in initial state
        let isInterviewing = await service.isInterviewing
        #expect(isInterviewing == false)
    }

    @Test("InterviewService should be initializable with IPC client and TTS engine")
    func testInitializationWithIPCClientAndTTS() async {
        let mockClient = MockInterviewIPCClient()
        let mockTTS = MockInterviewTTSEngine()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: mockTTS)

        let isInterviewing = await service.isInterviewing
        #expect(isInterviewing == false)
    }

    @Test("InterviewService should start with nil currentSession")
    func testInitialCurrentSessionIsNil() async {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        let session = await service.currentSession
        #expect(session == nil)
    }

    @Test("InterviewService should have transcriptManager")
    func testHasTranscriptManager() async {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        let transcriptManager = await service.transcriptManager
        #expect(transcriptManager.count == 0)
    }

    @Test("InterviewService should accept delegate")
    func testSetDelegate() async {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()

        await service.setDelegate(delegate)
        // Should not crash, delegate is set
    }
}

// MARK: - Task 6.2.1: Interview Lifecycle - Start Tests

@Suite("InterviewService Start Interview")
struct InterviewServiceStartTests {

    @Test("startInterview should create new session")
    func testStartInterviewCreatesSession() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Let's start with requirements")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a URL shortener")

        let session = await service.currentSession
        #expect(session != nil)
        #expect(session?.question == "Design a URL shortener")
    }

    @Test("startInterview should set isInterviewing to true")
    func testStartInterviewSetsIsInterviewing() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        let isInterviewing = await service.isInterviewing
        #expect(isInterviewing == true)
    }

    @Test("startInterview should send interview_start IPC message")
    func testStartInterviewSendsIPCMessage() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a load balancer")

        let sentMessages = mockClient.sentMessages
        #expect(sentMessages.count >= 1)
        let startMessage = sentMessages.first { $0.type == .interviewStart }
        #expect(startMessage != nil)

        let payload = startMessage!.payload["question"]?.value as? String
        #expect(payload == "Design a load balancer")
    }

    @Test("startInterview should throw when not connected")
    func testStartInterviewThrowsWhenNotConnected() async {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = false
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        await #expect(throws: InterviewServiceError.notConnected) {
            try await service.startInterview(question: "Design a cache")
        }
    }

    @Test("startInterview should throw when already interviewing")
    func testStartInterviewThrowsWhenAlreadyInterviewing() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        await #expect(throws: InterviewServiceError.alreadyInterviewing) {
            try await service.startInterview(question: "Design another system")
        }
    }

    @Test("startInterview should throw on empty question")
    func testStartInterviewThrowsOnEmptyQuestion() async {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        await #expect(throws: InterviewServiceError.invalidQuestion) {
            try await service.startInterview(question: "")
        }
    }

    @Test("startInterview should throw on whitespace-only question")
    func testStartInterviewThrowsOnWhitespaceQuestion() async {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        await #expect(throws: InterviewServiceError.invalidQuestion) {
            try await service.startInterview(question: "   \t\n  ")
        }
    }

    @Test("startInterview should initialize session timer to 30 minutes")
    func testStartInterviewInitializesTimer() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        let session = await service.currentSession
        #expect(session?.remainingSeconds == 1800) // 30 minutes
    }

    @Test("startInterview should notify delegate of first question")
    func testStartInterviewNotifiesDelegate() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "What are the requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        try await service.startInterview(question: "Design a URL shortener")

        // Give time for async delegate notification
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        #expect(delegate.receivedQuestions.count >= 1)
        #expect(delegate.receivedQuestions.contains("What are the requirements?"))
    }

    @Test("startInterview should speak question via TTS if available")
    func testStartInterviewSpeaksQuestion() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "What are the requirements?")
        )
        let mockTTS = MockInterviewTTSEngine()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: mockTTS)

        try await service.startInterview(question: "Design a cache")

        // Give time for TTS to be called
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        #expect(mockTTS.spokenTexts.contains("What are the requirements?"))
    }
}

// MARK: - Task 6.2.1: Interview Lifecycle - Pause/Resume Tests

@Suite("InterviewService Pause/Resume")
struct InterviewServicePauseResumeTests {

    @Test("pauseInterview should set session isPaused to true")
    func testPauseInterview() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")
        await service.pauseInterview()

        let session = await service.currentSession
        #expect(session?.isPaused == true)
    }

    @Test("pauseInterview should stop TTS if speaking")
    func testPauseInterviewStopsTTS() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let mockTTS = MockInterviewTTSEngine()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: mockTTS)

        try await service.startInterview(question: "Design a cache")
        await service.pauseInterview()

        #expect(mockTTS.wasStopped == true)
    }

    @Test("pauseInterview should be no-op when not interviewing")
    func testPauseInterviewNoOpWhenNotInterviewing() async {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        await service.pauseInterview()

        // Should not crash or change state
        let isInterviewing = await service.isInterviewing
        #expect(isInterviewing == false)
    }

    @Test("resumeInterview should set session isPaused to false")
    func testResumeInterview() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")
        await service.pauseInterview()
        await service.resumeInterview()

        let session = await service.currentSession
        #expect(session?.isPaused == false)
    }

    @Test("resumeInterview should be no-op when not paused")
    func testResumeInterviewNoOpWhenNotPaused() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        let sessionBefore = await service.currentSession
        #expect(sessionBefore?.isPaused == false)

        await service.resumeInterview()

        let sessionAfter = await service.currentSession
        #expect(sessionAfter?.isPaused == false)
    }

    @Test("multiple pause/resume cycles should work correctly")
    func testMultiplePauseResumeCycles() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        for _ in 0..<5 {
            await service.pauseInterview()
            var session = await service.currentSession
            #expect(session?.isPaused == true)

            await service.resumeInterview()
            session = await service.currentSession
            #expect(session?.isPaused == false)
        }
    }
}

// MARK: - Task 6.2.1: Interview Lifecycle - End Tests

@Suite("InterviewService End Interview")
struct InterviewServiceEndTests {

    @Test("endInterview should set isInterviewing to false")
    func testEndInterviewSetsIsInterviewing() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")
        try await service.endInterview()

        let isInterviewing = await service.isInterviewing
        #expect(isInterviewing == false)
    }

    @Test("endInterview should send interview_end IPC message")
    func testEndInterviewSendsIPCMessage() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")
        mockClient.sentMessages = [] // Clear previous messages
        try await service.endInterview()

        let sentMessages = mockClient.sentMessages
        let endMessage = sentMessages.first { $0.type == .interviewEnd }
        #expect(endMessage != nil)
    }

    @Test("endInterview should clear currentSession")
    func testEndInterviewClearsSession() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")
        try await service.endInterview()

        let session = await service.currentSession
        #expect(session == nil)
    }

    @Test("endInterview should throw when not interviewing")
    func testEndInterviewThrowsWhenNotInterviewing() async {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        await #expect(throws: InterviewServiceError.notInterviewing) {
            try await service.endInterview()
        }
    }

    @Test("endInterview should stop TTS if speaking")
    func testEndInterviewStopsTTS() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let mockTTS = MockInterviewTTSEngine()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: mockTTS)

        try await service.startInterview(question: "Design a cache")
        try await service.endInterview()

        #expect(mockTTS.wasStopped == true)
    }

    @Test("endInterview should notify delegate of completion")
    func testEndInterviewNotifiesDelegate() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        try await service.startInterview(question: "Design a cache")
        try await service.endInterview()

        // Give time for async delegate notification
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        #expect(delegate.didComplete == true)
    }

    @Test("endInterview should preserve transcript history")
    func testEndInterviewPreservesTranscripts() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        // Simulate receiving transcription
        let transcriptionMessage = IPCMessage.transcription(text: "Test response", isFinal: true)
        await service.handleIPCMessage(transcriptionMessage)

        try await service.endInterview()

        // Transcript should still be accessible
        let transcriptManager = await service.transcriptManager
        #expect(transcriptManager.count >= 1)
    }
}

// MARK: - Task 6.2.2: IPC Message Coordination Tests

@Suite("InterviewService IPC Message Handling")
struct InterviewServiceIPCTests {

    @Test("handleIPCMessage should process interview_question")
    func testHandleInterviewQuestion() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        try await service.startInterview(question: "Design a cache")

        // Handle follow-up question
        let questionMessage = IPCMessage.interviewQuestion(question: "What about scalability?")
        await service.handleIPCMessage(questionMessage)

        // Give time for async processing
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        #expect(delegate.receivedQuestions.contains("What about scalability?"))
    }

    @Test("handleIPCMessage should process interview_followup")
    func testHandleInterviewFollowup() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        try await service.startInterview(question: "Design a cache")

        let followupMessage = IPCMessage.interviewFollowup(question: "Can you elaborate on that?")
        await service.handleIPCMessage(followupMessage)

        // Give time for async processing
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        #expect(delegate.receivedFollowUps.contains("Can you elaborate on that?"))
    }

    @Test("handleIPCMessage should process transcription with partial result")
    func testHandleTranscriptionPartial() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        try await service.startInterview(question: "Design a cache")

        let transcriptionMessage = IPCMessage.transcription(text: "I think we should", isFinal: false)
        await service.handleIPCMessage(transcriptionMessage)

        // Give time for async processing
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let partialTranscriptions = delegate.receivedTranscriptions.filter { !$0.isFinal }
        #expect(partialTranscriptions.count >= 1)
    }

    @Test("handleIPCMessage should process transcription with final result")
    func testHandleTranscriptionFinal() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        try await service.startInterview(question: "Design a cache")

        let transcriptionMessage = IPCMessage.transcription(text: "I think we should use Redis", isFinal: true)
        await service.handleIPCMessage(transcriptionMessage)

        // Give time for async processing
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let finalTranscriptions = delegate.receivedTranscriptions.filter { $0.isFinal }
        #expect(finalTranscriptions.count >= 1)
        #expect(finalTranscriptions.first?.text == "I think we should use Redis")
    }

    @Test("handleIPCMessage should add final transcription to transcript manager")
    func testFinalTranscriptionAddedToManager() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        let transcriptionMessage = IPCMessage.transcription(text: "User response here", isFinal: true)
        await service.handleIPCMessage(transcriptionMessage)

        let transcriptManager = await service.transcriptManager
        let entries = transcriptManager.entries
        let userEntries = entries.filter { $0.source == .user }
        #expect(userEntries.count >= 1)
        #expect(userEntries.last?.content == "User response here")
    }

    @Test("handleIPCMessage should process feedback_response")
    func testHandleFeedbackResponse() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        try await service.startInterview(question: "Design a cache")

        let feedbackMarkdown = "## Feedback\n\nGreat job!"
        let feedbackMessage = IPCMessage.feedbackResponse(markdown: feedbackMarkdown)
        await service.handleIPCMessage(feedbackMessage)

        // Give time for async processing
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        #expect(delegate.receivedFeedback.contains(feedbackMarkdown))
    }

    @Test("handleIPCMessage should speak questions via TTS")
    func testHandleIPCMessageSpeaksQuestion() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let mockTTS = MockInterviewTTSEngine()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: mockTTS)

        try await service.startInterview(question: "Design a cache")

        let questionMessage = IPCMessage.interviewQuestion(question: "How would you scale this?")
        await service.handleIPCMessage(questionMessage)

        // Give time for TTS
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        #expect(mockTTS.spokenTexts.contains("How would you scale this?"))
    }

    @Test("handleIPCMessage should increment follow-up count")
    func testHandleFollowupIncrementsCount() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        var session = await service.currentSession
        let initialCount = session?.followUpCount ?? 0

        let followupMessage = IPCMessage.interviewFollowup(question: "Can you elaborate?")
        await service.handleIPCMessage(followupMessage)

        session = await service.currentSession
        #expect(session?.followUpCount == initialCount + 1)
    }

    @Test("handleIPCMessage should ignore messages when not interviewing")
    func testHandleIPCMessageIgnoredWhenNotInterviewing() async {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        let questionMessage = IPCMessage.interviewQuestion(question: "Should be ignored")
        await service.handleIPCMessage(questionMessage)

        // Give time for async processing
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        #expect(delegate.receivedQuestions.isEmpty)
    }
}

// MARK: - Task 6.2.2: Send User Response Tests

@Suite("InterviewService Send User Response")
struct InterviewServiceSendResponseTests {

    @Test("sendUserResponse should send interview_response IPC message")
    func testSendUserResponse() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")
        mockClient.sentMessages = [] // Clear previous messages

        try await service.sendUserResponse("I would use a distributed cache")

        let sentMessages = mockClient.sentMessages
        let responseMessage = sentMessages.first { $0.type == .interviewResponse }
        #expect(responseMessage != nil)

        let payload = responseMessage!.payload["response"]?.value as? String
        #expect(payload == "I would use a distributed cache")
    }

    @Test("sendUserResponse should throw when not interviewing")
    func testSendUserResponseThrowsWhenNotInterviewing() async {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        await #expect(throws: InterviewServiceError.notInterviewing) {
            try await service.sendUserResponse("Test response")
        }
    }

    @Test("sendUserResponse should add response to transcript manager")
    func testSendUserResponseAddedToTranscript() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")
        try await service.sendUserResponse("My detailed response")

        let transcriptManager = await service.transcriptManager
        let entries = transcriptManager.entries
        let userEntries = entries.filter { $0.source == .user }
        #expect(userEntries.last?.content == "My detailed response")
    }

    @Test("sendUserResponse should interrupt TTS if speaking")
    func testSendUserResponseInterruptsTTS() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let mockTTS = MockInterviewTTSEngine()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: mockTTS)

        try await service.startInterview(question: "Design a cache")
        try await service.sendUserResponse("User is speaking now")

        #expect(mockTTS.wasInterrupted == true)
    }
}

// MARK: - Task 6.2.3: Feedback Request Tests

@Suite("InterviewService Feedback Request")
struct InterviewServiceFeedbackTests {

    @Test("requestFeedback should send feedback_request IPC message")
    func testRequestFeedbackSendsMessage() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        mockClient.setSimulatedResponse(
            for: .feedbackRequest,
            response: IPCMessage.feedbackResponse(markdown: "## Feedback\n\nGreat!")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")
        mockClient.sentMessages = [] // Clear previous messages

        _ = try await service.requestFeedback()

        let sentMessages = mockClient.sentMessages
        let feedbackMessage = sentMessages.first { $0.type == .feedbackRequest }
        #expect(feedbackMessage != nil)
    }

    @Test("requestFeedback should include transcript in payload")
    func testRequestFeedbackIncludesTranscript() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "What are the requirements?")
        )
        mockClient.setSimulatedResponse(
            for: .feedbackRequest,
            response: IPCMessage.feedbackResponse(markdown: "## Feedback")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        // Simulate conversation
        let transcriptionMessage = IPCMessage.transcription(text: "100 million requests", isFinal: true)
        await service.handleIPCMessage(transcriptionMessage)

        mockClient.sentMessages = []
        _ = try await service.requestFeedback()

        let sentMessages = mockClient.sentMessages
        let feedbackMessage = sentMessages.first { $0.type == .feedbackRequest }

        #expect(feedbackMessage != nil)
        let transcript = feedbackMessage!.payload["transcript"]?.value
        #expect(transcript != nil)
    }

    @Test("requestFeedback should return markdown response")
    func testRequestFeedbackReturnsMarkdown() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        let expectedMarkdown = "## Feedback\n\n### Strengths\n- Good analysis"
        mockClient.setSimulatedResponse(
            for: .feedbackRequest,
            response: IPCMessage.feedbackResponse(markdown: expectedMarkdown)
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")
        let feedback = try await service.requestFeedback()

        #expect(feedback == expectedMarkdown)
    }

    @Test("requestFeedback should throw when not interviewing")
    func testRequestFeedbackThrowsWhenNotInterviewing() async {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        await #expect(throws: InterviewServiceError.notInterviewing) {
            _ = try await service.requestFeedback()
        }
    }

    @Test("requestFeedback should throw on IPC timeout")
    func testRequestFeedbackThrowsOnTimeout() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial question")
        )
        // No response set for feedbackRequest, will timeout
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        await #expect(throws: Error.self) {
            _ = try await service.requestFeedback()
        }
    }
}

// MARK: - Task 6.2.3: Save Feedback Tests

@Suite("InterviewService Save Feedback")
struct InterviewServiceSaveFeedbackTests {

    @Test("saveFeedback should write markdown to file")
    func testSaveFeedbackWritesToFile() async throws {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        let markdown = "## Interview Feedback\n\nGreat job!"
        let tempPath = NSTemporaryDirectory() + "test_feedback_\(UUID().uuidString).md"

        try await service.saveFeedback(markdown, to: tempPath)

        let savedContent = try String(contentsOfFile: tempPath, encoding: .utf8)
        #expect(savedContent == markdown)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test("saveFeedback should throw on invalid path")
    func testSaveFeedbackThrowsOnInvalidPath() async {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        let markdown = "## Feedback"
        let invalidPath = "/nonexistent/directory/feedback.md"

        await #expect(throws: InterviewServiceError.self) {
            try await service.saveFeedback(markdown, to: invalidPath)
        }
    }

    @Test("saveFeedback should handle empty markdown")
    func testSaveFeedbackHandlesEmptyMarkdown() async throws {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        let tempPath = NSTemporaryDirectory() + "test_empty_\(UUID().uuidString).md"

        try await service.saveFeedback("", to: tempPath)

        let savedContent = try String(contentsOfFile: tempPath, encoding: .utf8)
        #expect(savedContent == "")

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test("saveFeedback should handle unicode content")
    func testSaveFeedbackHandlesUnicode() async throws {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        let markdown = "## Feedback\n\nExcellent work! Great analysis."
        let tempPath = NSTemporaryDirectory() + "test_unicode_\(UUID().uuidString).md"

        try await service.saveFeedback(markdown, to: tempPath)

        let savedContent = try String(contentsOfFile: tempPath, encoding: .utf8)
        #expect(savedContent == markdown)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test("saveFeedback should overwrite existing file")
    func testSaveFeedbackOverwritesExisting() async throws {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        let tempPath = NSTemporaryDirectory() + "test_overwrite_\(UUID().uuidString).md"

        // Write initial content
        try "Old content".write(toFile: tempPath, atomically: true, encoding: .utf8)

        // Overwrite with new content
        let newMarkdown = "## New Feedback"
        try await service.saveFeedback(newMarkdown, to: tempPath)

        let savedContent = try String(contentsOfFile: tempPath, encoding: .utf8)
        #expect(savedContent == newMarkdown)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }
}

// MARK: - Transcript Accumulation Tests

@Suite("InterviewService Transcript Accumulation")
struct InterviewServiceTranscriptTests {

    @Test("Transcript manager should accumulate interviewer questions")
    func testTranscriptAccumulatesQuestions() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "What are the requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        // Wait for initial question to be processed
        try await Task.sleep(nanoseconds: 100_000_000)

        let transcriptManager = await service.transcriptManager
        let interviewerEntries = transcriptManager.entries.filter { $0.source == .interviewer }
        #expect(interviewerEntries.count >= 1)
    }

    @Test("Transcript manager should accumulate user responses")
    func testTranscriptAccumulatesResponses() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        // Simulate user response
        let transcription1 = IPCMessage.transcription(text: "First response", isFinal: true)
        await service.handleIPCMessage(transcription1)

        let transcription2 = IPCMessage.transcription(text: "Second response", isFinal: true)
        await service.handleIPCMessage(transcription2)

        let transcriptManager = await service.transcriptManager
        let userEntries = transcriptManager.entries.filter { $0.source == .user }
        #expect(userEntries.count >= 2)
    }

    @Test("Transcript manager should maintain conversation order")
    func testTranscriptMaintainsOrder() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Q1")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")
        try await Task.sleep(nanoseconds: 50_000_000) // Wait for Q1

        let response1 = IPCMessage.transcription(text: "A1", isFinal: true)
        await service.handleIPCMessage(response1)

        let followup = IPCMessage.interviewFollowup(question: "Q2")
        await service.handleIPCMessage(followup)

        let response2 = IPCMessage.transcription(text: "A2", isFinal: true)
        await service.handleIPCMessage(response2)

        let transcriptManager = await service.transcriptManager
        let entries = transcriptManager.entries

        // Verify alternating pattern: interviewer, user, interviewer, user
        #expect(entries.count >= 4)
        #expect(entries[0].source == .interviewer)
        #expect(entries[1].source == .user)
        #expect(entries[2].source == .interviewer)
        #expect(entries[3].source == .user)
    }

    @Test("Transcript manager should not include partial transcriptions")
    func testTranscriptExcludesPartial() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        // Send partial transcription
        let partial = IPCMessage.transcription(text: "I think", isFinal: false)
        await service.handleIPCMessage(partial)

        // Send final transcription
        let final = IPCMessage.transcription(text: "I think we need caching", isFinal: true)
        await service.handleIPCMessage(final)

        let transcriptManager = await service.transcriptManager
        let userEntries = transcriptManager.entries.filter { $0.source == .user }

        // Should only have the final transcription
        #expect(userEntries.count == 1)
        #expect(userEntries.first?.content == "I think we need caching")
    }
}

// MARK: - Delegate Callback Tests

@Suite("InterviewService Delegate Callbacks")
struct InterviewServiceDelegateTests {

    @Test("Delegate should receive all question types")
    func testDelegateReceivesAllQuestions() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Initial Q")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        try await service.startInterview(question: "Design a cache")
        try await Task.sleep(nanoseconds: 50_000_000)

        let question2 = IPCMessage.interviewQuestion(question: "Follow Q")
        await service.handleIPCMessage(question2)

        let followup = IPCMessage.interviewFollowup(question: "Deep dive Q")
        await service.handleIPCMessage(followup)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(delegate.receivedQuestions.count >= 2)
        #expect(delegate.receivedFollowUps.count >= 1)
    }

    @Test("Delegate should receive transcription updates")
    func testDelegateReceivesTranscriptionUpdates() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        try await service.startInterview(question: "Design a cache")

        let partial1 = IPCMessage.transcription(text: "I", isFinal: false)
        await service.handleIPCMessage(partial1)

        let partial2 = IPCMessage.transcription(text: "I think", isFinal: false)
        await service.handleIPCMessage(partial2)

        let final = IPCMessage.transcription(text: "I think we need Redis", isFinal: true)
        await service.handleIPCMessage(final)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(delegate.receivedTranscriptions.count >= 3)

        let finalTranscriptions = delegate.receivedTranscriptions.filter { $0.isFinal }
        #expect(finalTranscriptions.count >= 1)
    }

    @Test("Delegate should be notified on completion")
    func testDelegateNotifiedOnCompletion() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        try await service.startInterview(question: "Design a cache")
        try await service.endInterview()

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(delegate.didComplete == true)
    }

    @Test("Delegate can be changed during interview")
    func testDelegateCanBeChanged() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        let delegate1 = MockInterviewServiceDelegate()
        await service.setDelegate(delegate1)

        try await service.startInterview(question: "Design a cache")
        try await Task.sleep(nanoseconds: 50_000_000)

        // Change delegate
        let delegate2 = MockInterviewServiceDelegate()
        await service.setDelegate(delegate2)

        let followup = IPCMessage.interviewFollowup(question: "New question")
        await service.handleIPCMessage(followup)

        try await Task.sleep(nanoseconds: 100_000_000)

        // New delegate should receive follow-up
        #expect(delegate2.receivedFollowUps.contains("New question"))
    }

    @Test("Nil delegate should not crash")
    func testNilDelegateNoCrash() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        // No delegate set
        try await service.startInterview(question: "Design a cache")

        let question = IPCMessage.interviewQuestion(question: "Test")
        await service.handleIPCMessage(question)

        let transcription = IPCMessage.transcription(text: "Response", isFinal: true)
        await service.handleIPCMessage(transcription)

        try await service.endInterview()

        // Should complete without crash
        let isInterviewing = await service.isInterviewing
        #expect(isInterviewing == false)
    }
}

// MARK: - Error Handling Tests

@Suite("InterviewService Error Handling")
struct InterviewServiceErrorTests {

    @Test("IPC send failure should throw error")
    func testIPCSendFailure() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.shouldThrowOnSend = true
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        await #expect(throws: Error.self) {
            try await service.startInterview(question: "Design a cache")
        }
    }

    @Test("Service should handle IPC disconnection gracefully")
    func testHandlesDisconnection() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        // Simulate disconnection
        mockClient.simulateConnected = false
        mockClient.shouldThrowOnSend = true

        // Operations should handle disconnection gracefully
        await service.pauseInterview() // Should not crash

        let session = await service.currentSession
        #expect(session != nil) // Session should still exist
    }

    @Test("Service should handle TTS errors gracefully")
    func testHandlesTTSErrors() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        // Note: MockInterviewTTSEngine doesn't throw, but real implementation might
        let mockTTS = MockInterviewTTSEngine()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: mockTTS)

        try await service.startInterview(question: "Design a cache")

        // Should not crash even if TTS has issues
        let isInterviewing = await service.isInterviewing
        #expect(isInterviewing == true)
    }
}

// MARK: - Thread Safety Tests

@Suite("InterviewService Thread Safety")
struct InterviewServiceThreadSafetyTests {

    @Test("Concurrent state reads should be safe")
    func testConcurrentStateReads() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = await service.isInterviewing
                    _ = await service.currentSession
                    _ = await service.transcriptManager
                }
            }
        }

        // Should complete without crash
        let isInterviewing = await service.isInterviewing
        #expect(isInterviewing == true)
    }

    @Test("Concurrent message handling should be safe")
    func testConcurrentMessageHandling() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let message = IPCMessage.transcription(text: "Response \(i)", isFinal: i % 2 == 0)
                    await service.handleIPCMessage(message)
                }
            }
        }

        // Should complete without crash
        let transcriptManager = await service.transcriptManager
        #expect(transcriptManager.count >= 0)
    }

    @Test("InterviewService should be Sendable")
    func testSendable() async throws {
        let mockClient = MockInterviewIPCClient()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                return await service.isInterviewing
            }

            for await result in group {
                #expect(result == false)
            }
        }
    }
}

// MARK: - Integration-like Tests

@Suite("InterviewService Integration")
struct InterviewServiceIntegrationTests {

    @Test("Full interview flow simulation")
    func testFullInterviewFlow() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "What are the requirements?")
        )
        mockClient.setSimulatedResponse(
            for: .feedbackRequest,
            response: IPCMessage.feedbackResponse(markdown: "## Feedback\n\nGood job!")
        )
        let mockTTS = MockInterviewTTSEngine()
        let service = InterviewService(ipcClient: mockClient, ttsEngine: mockTTS)
        let delegate = MockInterviewServiceDelegate()
        await service.setDelegate(delegate)

        // 1. Start interview
        try await service.startInterview(question: "Design a URL shortener")
        try await Task.sleep(nanoseconds: 50_000_000)

        var isInterviewing = await service.isInterviewing
        #expect(isInterviewing == true)
        #expect(mockTTS.spokenTexts.count >= 1)

        // 2. User responds
        let response1 = IPCMessage.transcription(text: "100 million URLs", isFinal: true)
        await service.handleIPCMessage(response1)

        // 3. Follow-up question
        let followup = IPCMessage.interviewFollowup(question: "How would you store them?")
        await service.handleIPCMessage(followup)
        try await Task.sleep(nanoseconds: 50_000_000)

        // 4. User responds again
        let response2 = IPCMessage.transcription(text: "Key-value store", isFinal: true)
        await service.handleIPCMessage(response2)

        // 5. Pause/Resume
        await service.pauseInterview()
        var session = await service.currentSession
        #expect(session?.isPaused == true)

        await service.resumeInterview()
        session = await service.currentSession
        #expect(session?.isPaused == false)

        // 6. Request feedback
        let feedback = try await service.requestFeedback()
        #expect(feedback.contains("Feedback"))

        // 7. Save feedback
        let tempPath = NSTemporaryDirectory() + "integration_test_\(UUID().uuidString).md"
        try await service.saveFeedback(feedback, to: tempPath)
        let savedContent = try String(contentsOfFile: tempPath, encoding: .utf8)
        #expect(savedContent == feedback)

        // 8. End interview
        try await service.endInterview()
        isInterviewing = await service.isInterviewing
        #expect(isInterviewing == false)

        // Verify delegate received all events
        #expect(delegate.receivedQuestions.count >= 1)
        #expect(delegate.receivedFollowUps.count >= 1)
        #expect(delegate.receivedTranscriptions.count >= 2)
        #expect(delegate.didComplete == true)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test("Interview with timeout scenario")
    func testInterviewTimeout() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        try await service.startInterview(question: "Design a cache")

        // Simulate time passing
        let session = await service.currentSession
        let initialTime = session?.remainingSeconds ?? 0

        // Session timer would decrement in real implementation
        // This test verifies the session tracks time
        #expect(initialTime == 1800)
    }

    @Test("Multiple interview sessions")
    func testMultipleInterviewSessions() async throws {
        let mockClient = MockInterviewIPCClient()
        mockClient.simulateConnected = true
        mockClient.setSimulatedResponse(
            for: .interviewStart,
            response: IPCMessage.interviewQuestion(question: "Requirements?")
        )
        let service = InterviewService(ipcClient: mockClient, ttsEngine: nil)

        // First interview
        try await service.startInterview(question: "Design a cache")
        try await service.endInterview()

        // Second interview
        try await service.startInterview(question: "Design a queue")
        let session = await service.currentSession
        #expect(session?.question == "Design a queue")
        #expect(session?.remainingSeconds == 1800) // Fresh timer

        try await service.endInterview()

        // Verify clean state
        let isInterviewing = await service.isInterviewing
        #expect(isInterviewing == false)
    }
}
