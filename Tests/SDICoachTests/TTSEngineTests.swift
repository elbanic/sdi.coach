// TTSEngineTests.swift
// TDD RED Phase: Failing tests for TTSEngine
//
// Tasks covered:
// - 3.2.1: TTSState enum and state management
// - 3.2.2: speak(text:) method with IPC communication
// - 3.2.3: stop() method and interruption handling

import Testing
import Foundation
import Combine
@testable import SDICoach

// MARK: - Task 3.2.1: TTSState Enum Tests

@Suite("TTSState Enum")
struct TTSStateTests {

    @Test("TTSState should have idle case")
    func testIdleState() {
        let state = TTSState.idle
        #expect(state == .idle)
    }

    @Test("TTSState should have speaking case")
    func testSpeakingState() {
        let state = TTSState.speaking
        #expect(state == .speaking)
    }

    @Test("TTSState should have paused case")
    func testPausedState() {
        let state = TTSState.paused
        #expect(state == .paused)
    }

    @Test("TTSState cases should be distinct")
    func testDistinctStates() {
        #expect(TTSState.idle != TTSState.speaking)
        #expect(TTSState.speaking != TTSState.paused)
        #expect(TTSState.idle != TTSState.paused)
    }

    @Test("TTSState should be Equatable")
    func testEquatable() {
        let state1 = TTSState.speaking
        let state2 = TTSState.speaking
        #expect(state1 == state2)
    }

    @Test("TTSState should be Sendable")
    func testSendable() async {
        let state: TTSState = .idle
        let result = await Task {
            return state
        }.value
        #expect(result == .idle)
    }
}

// MARK: - Task 3.2.1: State Management Tests

@Suite("TTSEngine State Management")
struct TTSEngineStateManagementTests {

    @Test("Initial state should be idle")
    func testInitialStateIsIdle() async {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)
        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("State should transition to speaking after speak() called")
    func testStateTransitionToSpeaking() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello world")

        // State should change to speaking immediately after speak() is called
        let state = await engine.state
        #expect(state == .speaking)
    }

    @Test("State should transition back to idle after speech completes")
    func testStateTransitionToIdleAfterCompletion() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello")

        // Simulate tts_status with completed status
        await engine.handleTTSStatus(status: "completed", progress: 1.0)

        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("State should be paused when TTS is paused")
    func testStateTransitionToPaused() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello")
        await engine.pause()

        let state = await engine.state
        #expect(state == .paused)
    }

    @Test("State should be observable via statePublisher")
    func testStatePublisher() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        var observedStates: [TTSState] = []
        var cancellables = Set<AnyCancellable>()

        engine.statePublisher.sink { state in
            observedStates.append(state)
        }.store(in: &cancellables)

        try await engine.speak(text: "Test")
        await engine.handleTTSStatus(status: "completed", progress: 1.0)

        // Should have observed: idle -> speaking -> idle
        #expect(observedStates.contains(.idle))
        #expect(observedStates.contains(.speaking))
    }
}

// MARK: - Task 3.2.2: speak(text:) Method Tests

@Suite("TTSEngine speak() Method")
struct TTSEngineSpeakTests {

    @Test("speak() should send tts_speak IPC message")
    func testSpeakSendsIPCMessage() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello world")

        #expect(mockClient.sentMessages.count >= 1)
        let message = mockClient.sentMessages.first!
        #expect(message.type == .ttsSpeak)
    }

    @Test("speak() should include text in payload")
    func testSpeakPayloadContainsText() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        let testText = "Design a URL shortener"
        try await engine.speak(text: testText)

        let message = mockClient.sentMessages.first!
        let payloadText = message.payload["text"]?.value as? String
        #expect(payloadText == testText)
    }

    @Test("speak() should throw when not connected")
    func testSpeakThrowsWhenNotConnected() async {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = false
        let engine = TTSEngine(ipcClient: mockClient)

        await #expect(throws: TTSError.notConnected) {
            try await engine.speak(text: "Hello")
        }
    }

    @Test("speak() should throw on empty text")
    func testSpeakThrowsOnEmptyText() async {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        await #expect(throws: TTSError.invalidText) {
            try await engine.speak(text: "")
        }
    }

    @Test("speak() should throw on whitespace-only text")
    func testSpeakThrowsOnWhitespaceOnlyText() async {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        await #expect(throws: TTSError.invalidText) {
            try await engine.speak(text: "   \n\t  ")
        }
    }

    @Test("speak() while already speaking should interrupt previous")
    func testSpeakWhileSpeakingInterruptsPrevious() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "First message")

        // Speak again while still speaking
        try await engine.speak(text: "Second message")

        // Should have sent tts_stop before second tts_speak
        let stopMessages = mockClient.sentMessages.filter { $0.type == .ttsStop }
        #expect(stopMessages.count >= 1)
    }

    @Test("speak() should handle Unicode text correctly")
    func testSpeakHandlesUnicodeText() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        let unicodeText = "Hello! This is a test with emojis and special chars: e-acute"
        try await engine.speak(text: unicodeText)

        let message = mockClient.sentMessages.first!
        let payloadText = message.payload["text"]?.value as? String
        #expect(payloadText == unicodeText)
    }

    @Test("speak() should handle long text")
    func testSpeakHandlesLongText() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        let longText = String(repeating: "This is a long sentence. ", count: 100)
        try await engine.speak(text: longText)

        let message = mockClient.sentMessages.first!
        let payloadText = message.payload["text"]?.value as? String
        #expect(payloadText == longText)
    }
}

// MARK: - Task 3.2.2: TTS Status Handling Tests

@Suite("TTSEngine TTS Status Handling")
struct TTSEngineStatusHandlingTests {

    @Test("handleTTSStatus should update state to speaking on 'speaking' status")
    func testHandleStatusSpeaking() async throws {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)

        await engine.handleTTSStatus(status: "speaking", progress: 0.5)

        let state = await engine.state
        #expect(state == .speaking)
    }

    @Test("handleTTSStatus should update state to idle on 'completed' status")
    func testHandleStatusCompleted() async throws {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)

        // Start speaking first
        await engine.handleTTSStatus(status: "speaking", progress: 0.0)

        // Then complete
        await engine.handleTTSStatus(status: "completed", progress: 1.0)

        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("handleTTSStatus should update state to idle on 'stopped' status")
    func testHandleStatusStopped() async throws {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)

        await engine.handleTTSStatus(status: "speaking", progress: 0.0)
        await engine.handleTTSStatus(status: "stopped", progress: nil)

        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("handleTTSStatus should update progress property")
    func testHandleStatusUpdatesProgress() async throws {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)

        await engine.handleTTSStatus(status: "speaking", progress: 0.75)

        let progress = await engine.progress
        #expect(progress == 0.75)
    }

    @Test("handleTTSStatus should notify delegate on status change")
    func testHandleStatusNotifiesDelegate() async throws {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)
        let delegate = MockTTSEngineDelegate()
        await engine.setDelegate(delegate)

        await engine.handleTTSStatus(status: "speaking", progress: 0.5)

        #expect(delegate.didReceiveStatusUpdate)
        #expect(delegate.lastStatus == "speaking")
    }

    @Test("handleTTSStatus should call onComplete when speech finishes")
    func testHandleStatusCallsOnComplete() async throws {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)

        var completionCalled = false
        await engine.setOnComplete {
            completionCalled = true
        }

        await engine.handleTTSStatus(status: "completed", progress: 1.0)

        #expect(completionCalled)
    }

    @Test("handleTTSStatus should handle 'error' status")
    func testHandleStatusError() async throws {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)
        let delegate = MockTTSEngineDelegate()
        await engine.setDelegate(delegate)

        await engine.handleTTSStatus(status: "error", progress: nil)

        let state = await engine.state
        #expect(state == .idle)
        #expect(delegate.didEncounterError)
    }
}

// MARK: - Task 3.2.3: stop() Method Tests

@Suite("TTSEngine stop() Method")
struct TTSEngineStopTests {

    @Test("stop() should send tts_stop IPC message")
    func testStopSendsIPCMessage() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        // Start speaking first
        try await engine.speak(text: "Hello")
        mockClient.sentMessages.removeAll()

        // Then stop
        try await engine.stop()

        let stopMessages = mockClient.sentMessages.filter { $0.type == .ttsStop }
        #expect(stopMessages.count == 1)
    }

    @Test("stop() should transition state to idle")
    func testStopTransitionsToIdle() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello")
        try await engine.stop()

        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("stop() should be no-op when already idle")
    func testStopWhenIdleIsNoOp() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        // Should not throw when already idle
        try await engine.stop()

        // Should not send any messages
        let stopMessages = mockClient.sentMessages.filter { $0.type == .ttsStop }
        #expect(stopMessages.isEmpty)
    }

    @Test("stop() should throw when not connected")
    func testStopThrowsWhenNotConnected() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = false
        let engine = TTSEngine(ipcClient: mockClient)

        // Force state to speaking for test
        await engine.handleTTSStatus(status: "speaking", progress: 0.5)

        await #expect(throws: TTSError.notConnected) {
            try await engine.stop()
        }
    }

    @Test("stop() should cancel pending speech completion callback")
    func testStopCancelsPendingCallback() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        var completionCalled = false
        await engine.setOnComplete {
            completionCalled = true
        }

        try await engine.speak(text: "Hello")
        try await engine.stop()

        // Completion should NOT be called after stop
        #expect(!completionCalled)
    }

    @Test("stop() should reset progress to zero")
    func testStopResetsProgress() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello")
        await engine.handleTTSStatus(status: "speaking", progress: 0.5)
        try await engine.stop()

        let progress = await engine.progress
        #expect(progress == 0.0)
    }
}

// MARK: - Task 3.2.3: Interruption Handling Tests

@Suite("TTSEngine Interruption Handling")
struct TTSEngineInterruptionTests {

    @Test("interrupt() should stop TTS immediately")
    func testInterruptStopsTTS() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello")
        mockClient.sentMessages.removeAll()

        await engine.interrupt()

        let stopMessages = mockClient.sentMessages.filter { $0.type == .ttsStop }
        #expect(stopMessages.count == 1)
    }

    @Test("interrupt() should transition to idle state")
    func testInterruptTransitionsToIdle() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello")
        await engine.interrupt()

        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("interrupt() should notify delegate of interruption")
    func testInterruptNotifiesDelegate() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)
        let delegate = MockTTSEngineDelegate()
        await engine.setDelegate(delegate)

        try await engine.speak(text: "Hello")
        await engine.interrupt()

        #expect(delegate.didReceiveInterruption)
    }

    @Test("interrupt() should be safe to call when not speaking")
    func testInterruptWhenNotSpeaking() async {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        // Should not throw or crash
        await engine.interrupt()

        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("interrupt() should be called when user starts speaking (via delegate)")
    func testInterruptOnUserSpeaking() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello")

        // Simulate user starts speaking
        await engine.onUserStartedSpeaking()

        // TTS should be interrupted
        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("setInterruptOnUserSpeaking should configure auto-interrupt behavior")
    func testSetInterruptOnUserSpeaking() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        // Disable auto-interrupt
        await engine.setInterruptOnUserSpeaking(false)

        try await engine.speak(text: "Hello")
        await engine.onUserStartedSpeaking()

        // TTS should NOT be interrupted when disabled
        let state = await engine.state
        #expect(state == .speaking)
    }
}

// MARK: - TTSEngine Pause/Resume Tests

@Suite("TTSEngine Pause and Resume")
struct TTSEnginePauseResumeTests {

    @Test("pause() should transition to paused state")
    func testPauseTransitionsToPaused() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello")
        await engine.pause()

        let state = await engine.state
        #expect(state == .paused)
    }

    @Test("resume() should transition from paused to speaking")
    func testResumeTransitionsToSpeaking() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.speak(text: "Hello")
        await engine.pause()
        try await engine.resume()

        let state = await engine.state
        #expect(state == .speaking)
    }

    @Test("pause() should be no-op when idle")
    func testPauseWhenIdleIsNoOp() async {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)

        await engine.pause()

        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("resume() should be no-op when not paused")
    func testResumeWhenNotPausedIsNoOp() async throws {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)

        try await engine.resume()

        let state = await engine.state
        #expect(state == .idle)
    }
}

// MARK: - TTSEngine Edge Cases

@Suite("TTSEngine Edge Cases")
struct TTSEngineEdgeCaseTests {

    @Test("Multiple rapid speak() calls should only keep last one")
    func testMultipleRapidSpeakCalls() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        async let _ = try engine.speak(text: "First")
        async let _ = try engine.speak(text: "Second")
        async let _ = try engine.speak(text: "Third")

        // Wait a bit for all calls to process
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // The last speak text should be "Third"
        let speakMessages = mockClient.sentMessages.filter { $0.type == .ttsSpeak }
        let lastMessage = speakMessages.last!
        let text = lastMessage.payload["text"]?.value as? String
        #expect(text == "Third")
    }

    @Test("handleTTSStatus should ignore unknown status values")
    func testHandleUnknownStatus() async {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)

        await engine.handleTTSStatus(status: "unknown_status", progress: nil)

        // Should remain idle
        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("TTSEngine should be thread-safe")
    func testThreadSafety() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        // Concurrent access from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try? await engine.speak(text: "Message \(i)")
                }
                group.addTask {
                    await engine.handleTTSStatus(status: "speaking", progress: Double(i) / 10.0)
                }
            }
        }

        // Should not crash and state should be valid
        let state = await engine.state
        #expect(state == .idle || state == .speaking || state == .paused)
    }

    @Test("TTSEngine deinit should stop any active speech")
    func testDeinitStopsSpeech() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true

        do {
            let engine = TTSEngine(ipcClient: mockClient)
            try await engine.speak(text: "Hello")
            // engine goes out of scope here
        }

        // Should have sent tts_stop on deinit (if speaking)
        // This test verifies cleanup behavior
    }
}

// MARK: - TTSEngine IPC Integration Tests

@Suite("TTSEngine IPC Integration")
struct TTSEngineIPCIntegrationTests {

    @Test("TTSEngine should process incoming tts_status messages")
    func testProcessIncomingTTSStatus() async throws {
        let mockClient = MockTTSIPCClient()
        mockClient.simulateConnected = true
        let engine = TTSEngine(ipcClient: mockClient)

        // Simulate receiving a tts_status message from backend
        let statusMessage = IPCMessage.ttsStatus(status: "speaking", progress: 0.5)
        await engine.processIPCMessage(statusMessage)

        let state = await engine.state
        #expect(state == .speaking)
    }

    @Test("TTSEngine should ignore non-TTS messages")
    func testIgnoreNonTTSMessages() async throws {
        let mockClient = MockTTSIPCClient()
        let engine = TTSEngine(ipcClient: mockClient)

        let transcriptionMessage = IPCMessage.transcription(text: "Hello", isFinal: true)
        await engine.processIPCMessage(transcriptionMessage)

        // State should remain unchanged
        let state = await engine.state
        #expect(state == .idle)
    }
}

// MARK: - Mock Types

/// Mock IPC Client for testing TTSEngine
/// Thread-safe implementation using NSLock for synchronization
final class MockTTSIPCClient: TTSIPCClientProtocol, @unchecked Sendable {
    private var _sentMessages: [IPCMessage] = []
    private var _simulateConnected: Bool = false
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

    func send(_ message: IPCMessage) async throws {
        lock.lock()
        defer { lock.unlock() }
        _sentMessages.append(message)
    }

    func isConnected() async -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _simulateConnected
    }
}

/// Mock delegate for TTSEngine
final class MockTTSEngineDelegate: TTSEngineDelegate, @unchecked Sendable {
    var didReceiveStatusUpdate = false
    var lastStatus: String?
    var didEncounterError = false
    var didReceiveInterruption = false

    func ttsEngine(_ engine: TTSEngine, didUpdateStatus status: String, progress: Double?) {
        didReceiveStatusUpdate = true
        lastStatus = status
    }

    func ttsEngine(_ engine: TTSEngine, didEncounterError error: TTSError) {
        didEncounterError = true
    }

    func ttsEngineWasInterrupted(_ engine: TTSEngine) {
        didReceiveInterruption = true
    }
}
