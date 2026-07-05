// TUIEngineTests.swift
// TDD RED Phase: Failing tests for TUIEngine
//
// Task 5.3.1: TUIEngine - Main event loop, state management, component coordination
//
// Test framework: swift-testing (NOT XCTest)
// Feature: sdi.coach TUI Components

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 5.3.1: TUIEngine Main Loop Tests

@Suite("TUIEngine Initialization")
struct TUIEngineInitializationTests {

    @Test("TUIEngine should be initializable")
    func testTUIEngineInitializable() {
        let engine = TUIEngine()
        #expect(engine != nil)
    }

    @Test("TUIEngine should accept injected dependencies")
    func testTUIEngineWithDependencies() {
        let mockRenderer = MockTUIRenderer()
        let mockInput = MockTUIInput()

        let engine = TUIEngine(renderer: mockRenderer, inputHandler: mockInput)
        #expect(engine != nil)
    }

    @Test("TUIEngine should start in idle mode")
    func testInitialModeIsIdle() {
        let engine = TUIEngine()
        #expect(engine.currentMode == .idle)
    }

    @Test("TUIEngine should have default terminal renderer")
    func testHasDefaultRenderer() {
        let engine = TUIEngine()
        #expect(engine.renderer != nil)
    }
}

@Suite("TUIEngine State Management")
struct TUIEngineStateManagementTests {

    @Test("TUIEngine mode should be observable")
    func testModeIsObservable() {
        let engine = TUIEngine()
        var observedModes: [ApplicationMode] = []

        engine.onModeChange { mode in
            observedModes.append(mode)
        }

        // Simulate mode changes
        engine.setMode(.interviewing)
        engine.setMode(.paused)

        #expect(observedModes.contains(.interviewing))
        #expect(observedModes.contains(.paused))
    }

    @Test("TUIEngine should track interview session state")
    func testTracksInterviewSessionState() {
        let engine = TUIEngine()

        #expect(engine.interviewSession == nil)

        // Start interview
        engine.startInterview(question: "Design a URL shortener")

        #expect(engine.interviewSession != nil)
        #expect(engine.interviewSession?.question == "Design a URL shortener")
    }

    @Test("TUIEngine should track remaining time")
    func testTracksRemainingTime() {
        let engine = TUIEngine()

        engine.startInterview(question: "Design a cache")

        // Should have 30 minutes (1800 seconds) initially
        #expect(engine.remainingSeconds == 1800)
    }

    @Test("TUIEngine should update remaining time")
    func testUpdatesRemainingTime() {
        let engine = TUIEngine()

        engine.startInterview(question: "Design a cache")
        engine.updateRemainingTime(1500)

        #expect(engine.remainingSeconds == 1500)
    }

    @Test("TUIEngine should format remaining time as MM:SS")
    func testFormatsRemainingTime() {
        let engine = TUIEngine()

        engine.startInterview(question: "Design a cache")
        engine.updateRemainingTime(1475) // 24 min 35 sec

        #expect(engine.formattedRemainingTime == "24:35")
    }

    @Test("TUIEngine should track microphone state")
    func testTracksMicrophoneState() {
        let engine = TUIEngine()

        #expect(engine.isMicrophoneOn == false)

        engine.setMicrophoneOn(true)
        #expect(engine.isMicrophoneOn == true)

        engine.setMicrophoneOn(false)
        #expect(engine.isMicrophoneOn == false)
    }
}

@Suite("TUIEngine Event Loop")
struct TUIEngineEventLoopTests {

    @Test("TUIEngine should start event loop")
    func testStartEventLoop() async {
        let mockInput = MockTUIInput()
        let engine = TUIEngine(inputHandler: mockInput)

        // Simulate quit command after a short delay
        mockInput.queueInput(.command(.quit))

        let task = Task {
            await engine.run()
        }

        // Wait briefly for event loop to process
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        task.cancel()

        // Should have processed quit and stopped
        #expect(engine.currentMode == .idle || engine.isRunning == false)
    }

    @Test("TUIEngine should process commands in event loop")
    func testProcessCommands() async {
        let mockInput = MockTUIInput()
        let engine = TUIEngine(inputHandler: mockInput)

        // Queue a start command followed by quit
        mockInput.queueInput(.command(.start(question: "Design Twitter")))
        mockInput.queueInput(.command(.quit))

        await engine.run()

        // Should have processed start command
        #expect(engine.interviewSession?.question == "Design Twitter")
    }

    @Test("TUIEngine should stop event loop on quit")
    func testStopsOnQuit() async {
        let mockInput = MockTUIInput()
        let engine = TUIEngine(inputHandler: mockInput)

        mockInput.queueInput(.command(.quit))

        await engine.run()

        #expect(engine.isRunning == false)
    }

    @Test("TUIEngine should handle async operations without blocking")
    func testAsyncOperations() async {
        let mockInput = MockTUIInput()
        let engine = TUIEngine(inputHandler: mockInput)

        let startTime = Date()

        mockInput.queueInput(.command(.quit))
        await engine.run()

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete quickly (< 1 second)
        #expect(elapsed < 1.0)
    }
}

@Suite("TUIEngine Component Coordination")
struct TUIEngineComponentCoordinationTests {

    @Test("TUIEngine should coordinate HeaderView updates")
    func testCoordinatesHeaderView() {
        let mockRenderer = MockTUIRenderer()
        let engine = TUIEngine(renderer: mockRenderer)

        engine.startInterview(question: "Design a rate limiter")

        // HeaderView should be notified to update
        #expect(mockRenderer.headerUpdateCount > 0)
    }

    @Test("TUIEngine should coordinate StatusBar updates")
    func testCoordinatesStatusBar() {
        let mockRenderer = MockTUIRenderer()
        let engine = TUIEngine(renderer: mockRenderer)

        engine.setMode(.interviewing)

        // StatusBar should be notified to update
        #expect(mockRenderer.statusBarUpdateCount > 0)
    }

    @Test("TUIEngine should coordinate TranscriptView updates")
    func testCoordinatesTranscriptView() {
        let mockRenderer = MockTUIRenderer()
        let engine = TUIEngine(renderer: mockRenderer)

        engine.addTranscript(source: .interviewer, content: "Tell me about your design")

        // TranscriptView should be notified to update
        #expect(mockRenderer.transcriptUpdateCount > 0)
    }

    @Test("TUIEngine should trigger full redraw on mode change")
    func testTriggerRedrawOnModeChange() {
        let mockRenderer = MockTUIRenderer()
        let engine = TUIEngine(renderer: mockRenderer)

        engine.setMode(.interviewing)

        #expect(mockRenderer.fullRedrawCount > 0)
    }

    @Test("TUIEngine should render prompt")
    func testRendersPrompt() {
        let mockRenderer = MockTUIRenderer()
        let engine = TUIEngine(renderer: mockRenderer)

        engine.renderPrompt()

        #expect(mockRenderer.promptRenderCount > 0)
    }
}

@Suite("TUIEngine Command Handling")
struct TUIEngineCommandHandlingTests {

    @Test("TUIEngine should handle /start command")
    func testHandleStartCommand() {
        let engine = TUIEngine()

        engine.handleCommand(.start(question: "Design a messaging system"))

        #expect(engine.currentMode == .interviewing)
        #expect(engine.interviewSession?.question == "Design a messaging system")
    }

    @Test("TUIEngine should handle /start with default question")
    func testHandleStartWithDefaultQuestion() {
        let engine = TUIEngine()

        engine.handleCommand(.start(question: nil))

        #expect(engine.currentMode == .interviewing)
        #expect(engine.interviewSession?.question != nil)
    }

    @Test("TUIEngine should handle /pause command")
    func testHandlePauseCommand() {
        let engine = TUIEngine()

        engine.handleCommand(.start(question: "Design a cache"))
        engine.handleCommand(.pause)

        #expect(engine.currentMode == .paused)
    }

    @Test("TUIEngine should handle /end command")
    func testHandleEndCommand() {
        let engine = TUIEngine()

        engine.handleCommand(.start(question: "Design a cache"))
        engine.handleCommand(.end)

        #expect(engine.currentMode == .feedback)
    }

    @Test("TUIEngine should ignore /pause when idle")
    func testIgnorePauseWhenIdle() {
        let engine = TUIEngine()

        engine.handleCommand(.pause)

        #expect(engine.currentMode == .idle)
    }

    @Test("TUIEngine should resume from pause with /start")
    func testResumeFromPause() {
        let engine = TUIEngine()

        engine.handleCommand(.start(question: "Design a cache"))
        let originalQuestion = engine.interviewSession?.question

        engine.handleCommand(.pause)
        engine.handleCommand(.start(question: nil))

        #expect(engine.currentMode == .interviewing)
        #expect(engine.interviewSession?.question == originalQuestion)
    }
}

@Suite("TUIEngine Transcript Management")
struct TUIEngineTranscriptManagementTests {

    @Test("TUIEngine should add interviewer transcript")
    func testAddInterviewerTranscript() {
        let engine = TUIEngine()

        engine.handleCommand(.start(question: "Design a cache"))
        engine.addTranscript(source: .interviewer, content: "What are the requirements?")

        let transcripts = engine.getTranscripts()
        #expect(transcripts.count == 1)
        #expect(transcripts.first?.source == .interviewer)
        #expect(transcripts.first?.content == "What are the requirements?")
    }

    @Test("TUIEngine should add user transcript")
    func testAddUserTranscript() {
        let engine = TUIEngine()

        engine.handleCommand(.start(question: "Design a cache"))
        engine.addTranscript(source: .user, content: "We need to support 100k requests per second")

        let transcripts = engine.getTranscripts()
        #expect(transcripts.count == 1)
        #expect(transcripts.first?.source == .user)
    }

    @Test("TUIEngine should timestamp transcripts")
    func testTimestampTranscripts() {
        let engine = TUIEngine()

        let beforeAdd = Date()
        engine.handleCommand(.start(question: "Design a cache"))
        engine.addTranscript(source: .interviewer, content: "Hello")
        let afterAdd = Date()

        let transcripts = engine.getTranscripts()
        #expect(transcripts.first != nil)

        let timestamp = transcripts.first!.timestamp
        #expect(timestamp >= beforeAdd)
        #expect(timestamp <= afterAdd)
    }

    @Test("TUIEngine should maintain transcript order")
    func testMaintainTranscriptOrder() {
        let engine = TUIEngine()

        engine.handleCommand(.start(question: "Design a cache"))
        engine.addTranscript(source: .interviewer, content: "First question")
        engine.addTranscript(source: .user, content: "First answer")
        engine.addTranscript(source: .interviewer, content: "Follow-up")

        let transcripts = engine.getTranscripts()
        #expect(transcripts.count == 3)
        #expect(transcripts[0].content == "First question")
        #expect(transcripts[1].content == "First answer")
        #expect(transcripts[2].content == "Follow-up")
    }

    @Test("TUIEngine should clear transcripts on new interview")
    func testClearTranscriptsOnNewInterview() {
        let engine = TUIEngine()

        engine.handleCommand(.start(question: "Design a cache"))
        engine.addTranscript(source: .interviewer, content: "Question")
        engine.handleCommand(.end)

        // Start new interview
        engine.handleCommand(.start(question: "Design a queue"))

        let transcripts = engine.getTranscripts()
        #expect(transcripts.isEmpty)
    }
}

@Suite("TUIEngine Error Handling")
struct TUIEngineErrorHandlingTests {

    @Test("TUIEngine should handle unknown commands gracefully")
    func testHandleUnknownCommand() {
        let engine = TUIEngine()

        // Should not crash
        engine.handleCommand(.unknown(input: "/foo"))

        #expect(engine.currentMode == .idle)
    }

    @Test("TUIEngine should show error message for unknown command")
    func testShowErrorForUnknownCommand() {
        let mockRenderer = MockTUIRenderer()
        let engine = TUIEngine(renderer: mockRenderer)

        engine.handleCommand(.unknown(input: "/invalid"))

        #expect(mockRenderer.lastErrorMessage != nil)
        #expect(mockRenderer.lastErrorMessage?.contains("unknown") == true ||
                mockRenderer.lastErrorMessage?.contains("Invalid") == true)
    }

    @Test("TUIEngine should show error when ending non-existent interview")
    func testErrorEndingNonExistentInterview() {
        let mockRenderer = MockTUIRenderer()
        let engine = TUIEngine(renderer: mockRenderer)

        engine.handleCommand(.end)

        #expect(mockRenderer.lastErrorMessage != nil)
    }
}

@Suite("TUIEngine Thread Safety")
struct TUIEngineThreadSafetyTests {

    @Test("TUIEngine should be thread-safe for state access")
    func testThreadSafeStateAccess() async {
        let engine = TUIEngine()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    if i % 2 == 0 {
                        engine.setMode(.interviewing)
                    } else {
                        engine.setMode(.idle)
                    }
                    _ = engine.currentMode
                }
            }
        }

        // Should complete without crash
        #expect(engine.currentMode == .idle || engine.currentMode == .interviewing)
    }

    @Test("TUIEngine should be thread-safe for transcript access")
    func testThreadSafeTranscriptAccess() async {
        let engine = TUIEngine()
        engine.handleCommand(.start(question: "Test"))

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    engine.addTranscript(source: .user, content: "Message \(i)")
                    _ = engine.getTranscripts()
                }
            }
        }

        // Should have accumulated transcripts
        let transcripts = engine.getTranscripts()
        #expect(transcripts.count > 0)
    }
}

// MARK: - Mock Types for TUIEngine Tests

/// Mock TUI renderer for testing component coordination
final class MockTUIRenderer: TUIRendering, @unchecked Sendable {
    private let lock = NSLock()

    private var _headerUpdateCount = 0
    private var _statusBarUpdateCount = 0
    private var _transcriptUpdateCount = 0
    private var _fullRedrawCount = 0
    private var _promptRenderCount = 0
    private var _lastErrorMessage: String?

    var headerUpdateCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _headerUpdateCount
    }

    var statusBarUpdateCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _statusBarUpdateCount
    }

    var transcriptUpdateCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _transcriptUpdateCount
    }

    var fullRedrawCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _fullRedrawCount
    }

    var promptRenderCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _promptRenderCount
    }

    var lastErrorMessage: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastErrorMessage
    }

    func updateHeader(question: String, remainingTime: String) {
        lock.lock()
        defer { lock.unlock() }
        _headerUpdateCount += 1
    }

    func updateStatusBar(mode: ApplicationMode, micOn: Bool, remainingTime: String) {
        lock.lock()
        defer { lock.unlock() }
        _statusBarUpdateCount += 1
    }

    func appendTranscript(source: TranscriptSource, content: String, timestamp: Date) {
        lock.lock()
        defer { lock.unlock() }
        _transcriptUpdateCount += 1
    }

    func fullRedraw() {
        lock.lock()
        defer { lock.unlock() }
        _fullRedrawCount += 1
    }

    func renderPrompt() {
        lock.lock()
        defer { lock.unlock() }
        _promptRenderCount += 1
    }

    func showError(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        _lastErrorMessage = message
    }
}

/// Mock TUI input for testing event loop
final class MockTUIInput: TUIInputProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var inputQueue: [TUIInputEvent] = []

    func queueInput(_ event: TUIInputEvent) {
        lock.lock()
        defer { lock.unlock() }
        inputQueue.append(event)
    }

    func nextInput() async -> TUIInputEvent? {
        lock.lock()
        defer { lock.unlock() }

        if inputQueue.isEmpty {
            return nil
        }
        return inputQueue.removeFirst()
    }
}
