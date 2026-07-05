// TUIEngine.swift
// Task 5.3.1: TUIEngine - Main event loop, state management, component coordination
//
// This is a stub file for compilation. Full implementation pending.

import Foundation

/// Main TUI engine for sdi.coach
/// Coordinates TUI components, manages state, and runs the event loop
///
/// To be implemented as part of Task 5.3.1
public final class TUIEngine: @unchecked Sendable {

    // MARK: - Properties

    /// Current application mode
    public private(set) var currentMode: ApplicationMode = .idle

    /// Current interview session (if any)
    public private(set) var interviewSession: InterviewSessionState?

    /// Remaining time in seconds
    public private(set) var remainingSeconds: Int = 1800

    /// Whether microphone is on
    public private(set) var isMicrophoneOn: Bool = false

    /// Whether the event loop is running
    public private(set) var isRunning: Bool = false

    /// Current status message displayed below prompt
    public private(set) var statusMessage: String = ""

    /// Status message type for styling
    public private(set) var statusType: StatusType = .info

    /// Renderer for TUI output
    public let renderer: TUIRendering?

    /// Input handler
    private let inputHandler: TUIInputProviding?

    /// Transcripts for current session
    private var transcripts: [TranscriptEntry] = []

    /// Mode change callbacks
    private var modeChangeCallbacks: [(ApplicationMode) -> Void] = []

    private let lock = NSLock()

    // MARK: - Initialization

    public init() {
        self.renderer = DefaultTUIRenderer()
        self.inputHandler = nil
    }

    public init(renderer: TUIRendering) {
        self.renderer = renderer
        self.inputHandler = nil
    }

    public init(inputHandler: TUIInputProviding) {
        self.renderer = DefaultTUIRenderer()
        self.inputHandler = inputHandler
    }

    public init(renderer: TUIRendering, inputHandler: TUIInputProviding) {
        self.renderer = renderer
        self.inputHandler = inputHandler
    }

    // MARK: - State Management

    /// Set application mode
    public func setMode(_ mode: ApplicationMode) {
        lock.lock()
        currentMode = mode
        lock.unlock()

        for callback in modeChangeCallbacks {
            callback(mode)
        }

        renderer?.updateStatusBar(mode: mode, micOn: isMicrophoneOn, remainingTime: formattedRemainingTime)
        renderer?.fullRedraw()
    }

    /// Register callback for mode changes
    public func onModeChange(_ callback: @escaping (ApplicationMode) -> Void) {
        lock.lock()
        modeChangeCallbacks.append(callback)
        lock.unlock()
    }

    /// Start an interview session
    public func startInterview(question: String?) {
        lock.lock()
        let sessionQuestion = question ?? "Design a system"
        interviewSession = InterviewSessionState(question: sessionQuestion)
        remainingSeconds = 1800
        transcripts = []
        currentMode = .interviewing
        lock.unlock()

        renderer?.updateHeader(question: sessionQuestion, remainingTime: formattedRemainingTime)
    }

    /// Update remaining time
    public func updateRemainingTime(_ seconds: Int) {
        lock.lock()
        remainingSeconds = seconds
        lock.unlock()
    }

    /// Set microphone state
    public func setMicrophoneOn(_ on: Bool) {
        lock.lock()
        isMicrophoneOn = on
        lock.unlock()
    }

    /// Update status message
    public func setStatus(_ message: String, type: StatusType = .info) {
        lock.lock()
        statusMessage = message
        statusType = type
        lock.unlock()
    }

    /// Clear status message
    public func clearStatus() {
        lock.lock()
        statusMessage = ""
        statusType = .info
        lock.unlock()
    }

    /// Formatted remaining time as MM:SS
    public var formattedRemainingTime: String {
        lock.lock()
        let seconds = remainingSeconds
        lock.unlock()

        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - Transcript Management

    /// Add a transcript entry
    public func addTranscript(source: TranscriptSource, content: String) {
        let entry = TranscriptEntry(source: source, content: content, timestamp: Date())

        lock.lock()
        transcripts.append(entry)
        lock.unlock()

        renderer?.appendTranscript(source: source, content: content, timestamp: entry.timestamp)
    }

    /// Get all transcripts
    public func getTranscripts() -> [TranscriptEntry] {
        lock.lock()
        defer { lock.unlock() }
        return transcripts
    }

    // MARK: - Event Loop

    /// Run the TUI event loop
    public func run() async {
        isRunning = true

        while isRunning {
            guard let input = await inputHandler?.nextInput() else {
                isRunning = false
                break
            }

            switch input {
            case .command(let cmd):
                handleCommand(cmd)
                if case .quit = cmd {
                    isRunning = false
                }
            case .transcript(let source, let content):
                addTranscript(source: source, content: content)
            case .timerTick(let seconds):
                updateRemainingTime(seconds)
            }
        }
    }

    // MARK: - Command Handling

    /// Handle a command
    public func handleCommand(_ command: Command) {
        switch command {
        case .start(let question):
            if currentMode == .idle || currentMode == .feedback {
                startInterview(question: question)
                setMode(.interviewing)
            } else if currentMode == .paused {
                setMode(.interviewing)
            }

        case .answer:
            // Handled by Application, not TUIEngine
            break

        case .pause:
            if currentMode == .interviewing {
                setMode(.paused)
            }

        case .end:
            if currentMode == .interviewing || currentMode == .paused {
                setMode(.feedback)
            } else {
                renderer?.showError("No active interview to end")
            }

        case .quit:
            isRunning = false

        case .unknown(let input):
            renderer?.showError("unknown command: \(input)")
        }
    }

    /// Render the prompt
    public func renderPrompt() {
        renderer?.renderPrompt()
    }
}

// MARK: - Supporting Types

/// Interview session state
public struct InterviewSessionState: Sendable {
    public let question: String
    public let startTime: Date

    public init(question: String) {
        self.question = question
        self.startTime = Date()
    }
}

// TranscriptEntry and TranscriptSource are defined in Session/TranscriptEntry.swift

/// Protocol for TUI rendering
public protocol TUIRendering: Sendable {
    func updateHeader(question: String, remainingTime: String)
    func updateStatusBar(mode: ApplicationMode, micOn: Bool, remainingTime: String)
    func appendTranscript(source: TranscriptSource, content: String, timestamp: Date)
    func fullRedraw()
    func renderPrompt()
    func showError(_ message: String)
}

/// Protocol for TUI input
public protocol TUIInputProviding: Sendable {
    func nextInput() async -> TUIInputEvent?
}

/// TUI input events
public enum TUIInputEvent: Sendable {
    case command(Command)
    case transcript(source: TranscriptSource, content: String)
    case timerTick(remainingSeconds: Int)
}

// MARK: - Status Type

/// Type of status message for styling
public enum StatusType: Sendable {
    case info       // General info (gray)
    case waiting    // Waiting for user action (yellow)
    case thinking   // LLM is processing (cyan/animated)
    case success    // Action completed (green)
    case error      // Error occurred (red)
}

// MARK: - Default TUI Renderer

/// Default TUI renderer implementation
public final class DefaultTUIRenderer: TUIRendering, @unchecked Sendable {
    private let lock = NSLock()

    public init() {}

    public func updateHeader(question: String, remainingTime: String) {
        // Default implementation - can be extended
    }

    public func updateStatusBar(mode: ApplicationMode, micOn: Bool, remainingTime: String) {
        // Default implementation - can be extended
    }

    public func appendTranscript(source: TranscriptSource, content: String, timestamp: Date) {
        // Default implementation - can be extended
    }

    public func fullRedraw() {
        // Default implementation - can be extended
    }

    public func renderPrompt() {
        // Default implementation - can be extended
    }

    public func showError(_ message: String) {
        // Default implementation - can be extended
    }
}
