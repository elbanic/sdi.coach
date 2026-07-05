// TTSEngine.swift
// TDD GREEN Phase: Implementation to pass all tests
//
// Tasks covered:
// - 3.2.1: TTSState enum and state management
// - 3.2.2: speak(text:) method with IPC communication
// - 3.2.3: stop() method and interruption handling

import Foundation
import Combine

// MARK: - TTSState

/// Represents the current state of the TTS engine
/// Task 3.2.1: TTS state management (idle/speaking/paused)
public enum TTSState: String, Sendable, Equatable {
    case idle
    case speaking
    case paused
}

// MARK: - TTSError

/// Errors that can occur during TTS operations
public enum TTSError: Error, LocalizedError, Sendable, Equatable {
    case notConnected
    case invalidText
    case speakFailed(String)
    case stopFailed(String)
    case backendError(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "TTS engine is not connected to backend"
        case .invalidText:
            return "Invalid text provided for TTS"
        case .speakFailed(let reason):
            return "TTS speak failed: \(reason)"
        case .stopFailed(let reason):
            return "TTS stop failed: \(reason)"
        case .backendError(let message):
            return "TTS backend error: \(message)"
        }
    }
}

// MARK: - TTSEngineDelegate

/// Protocol for receiving TTS engine callbacks
public protocol TTSEngineDelegate: AnyObject, Sendable {
    /// Called when TTS status is updated
    func ttsEngine(_ engine: TTSEngine, didUpdateStatus status: String, progress: Double?)

    /// Called when TTS encounters an error
    func ttsEngine(_ engine: TTSEngine, didEncounterError error: TTSError)

    /// Called when TTS is interrupted (e.g., user starts speaking)
    func ttsEngineWasInterrupted(_ engine: TTSEngine)
}

// MARK: - IPCClientProtocol for TTS

/// Protocol for IPC client operations needed by TTSEngine
/// This allows for dependency injection and testing with mock implementations
public protocol TTSIPCClientProtocol: AnyObject, Sendable {
    /// Send an IPC message to the backend
    func send(_ message: IPCMessage) async throws

    /// Check if the client is connected
    func isConnected() async -> Bool
}

// MARK: - TTSEngine

/// TTS Engine for coordinating text-to-speech via Python backend
/// Task 3.2.1-3.2.3: State management, IPC communication, interruption handling
public actor TTSEngine {

    // MARK: - Properties

    /// Current TTS state
    /// Task 3.2.1: State management with @Published property
    public private(set) var state: TTSState = .idle

    /// Current playback progress (0.0 to 1.0)
    public private(set) var progress: Double = 0.0

    /// Subject for publishing state changes
    /// Note: nonisolated(unsafe) allows cross-actor access - safe because CurrentValueSubject is thread-safe
    private nonisolated(unsafe) let stateSubject = CurrentValueSubject<TTSState, Never>(.idle)

    /// Publisher for state changes
    public nonisolated var statePublisher: AnyPublisher<TTSState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// Whether to automatically interrupt TTS when user starts speaking
    private var interruptOnUserSpeaking: Bool = true

    /// Completion callback for current speech
    private var onCompleteCallback: (() -> Void)?

    /// Delegate for receiving TTS events
    private weak var delegate: TTSEngineDelegate?

    /// IPC client for backend communication
    private let ipcClient: TTSIPCClientProtocol

    // MARK: - Initialization

    /// Initialize with an IPC client
    /// - Parameter ipcClient: Client for communicating with Python backend
    public init(ipcClient: TTSIPCClientProtocol) {
        self.ipcClient = ipcClient
    }

    // MARK: - Configuration

    /// Set the delegate for TTS events
    public func setDelegate(_ delegate: TTSEngineDelegate?) {
        self.delegate = delegate
    }

    /// Set callback for speech completion
    public func setOnComplete(_ callback: @escaping () -> Void) {
        self.onCompleteCallback = callback
    }

    /// Configure whether to interrupt TTS when user starts speaking
    /// Task 3.2.3: Interruption handling (user starts speaking)
    public func setInterruptOnUserSpeaking(_ enabled: Bool) {
        self.interruptOnUserSpeaking = enabled
    }

    // MARK: - Task 3.2.2: speak(text:) Method

    /// Speak the given text using TTS backend
    /// - Parameter text: The text to speak
    /// - Throws: TTSError if not connected or text is invalid
    public func speak(text: String) async throws {
        // Validate text is not empty or whitespace-only
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSError.invalidText
        }

        // Check connection
        let connected = await ipcClient.isConnected()
        guard connected else {
            throw TTSError.notConnected
        }

        // If already speaking, interrupt previous speech first
        if state == .speaking {
            try await sendStopMessage()
        }

        // Send tts_speak message
        let message = IPCMessage.ttsSpeak(text: text)
        try await ipcClient.send(message)

        // Update state to speaking
        updateState(.speaking)
    }

    // MARK: - Task 3.2.3: stop() Method

    /// Stop any currently playing TTS
    /// - Throws: TTSError if not connected while speaking
    public func stop() async throws {
        // No-op when already idle
        guard state != .idle else {
            return
        }

        // Check connection when trying to stop
        let connected = await ipcClient.isConnected()
        guard connected else {
            throw TTSError.notConnected
        }

        try await sendStopMessage()

        // Clear completion callback (stop cancels it)
        onCompleteCallback = nil

        // Reset progress
        progress = 0.0

        // Update state to idle
        updateState(.idle)
    }

    /// Send stop message to backend
    private func sendStopMessage() async throws {
        let stopMessage = IPCMessage.ttsStop()
        try await ipcClient.send(stopMessage)
    }

    // MARK: - Pause/Resume

    /// Pause the current TTS playback
    public func pause() {
        // Only pause if currently speaking
        guard state == .speaking else {
            return
        }
        updateState(.paused)
    }

    /// Resume paused TTS playback
    public func resume() async throws {
        // Only resume if currently paused
        guard state == .paused else {
            return
        }
        updateState(.speaking)
    }

    // MARK: - Task 3.2.3: Interruption Handling

    /// Interrupt TTS immediately (e.g., when user starts speaking)
    public func interrupt() async {
        // No-op if not speaking
        guard state == .speaking || state == .paused else {
            return
        }

        // Send stop message (ignore connection errors for interrupt)
        let connected = await ipcClient.isConnected()
        if connected {
            try? await sendStopMessage()
        }

        // Notify delegate of interruption
        delegate?.ttsEngineWasInterrupted(self)

        // Reset progress
        progress = 0.0

        // Update state to idle
        updateState(.idle)
    }

    /// Called when user starts speaking (from audio capture)
    public func onUserStartedSpeaking() async {
        // Only interrupt if flag is enabled and currently speaking
        guard interruptOnUserSpeaking, state == .speaking else {
            return
        }
        await interrupt()
    }

    // MARK: - Task 3.2.2: TTS Status Handling

    /// Handle TTS status update from backend
    /// - Parameters:
    ///   - status: Status string from backend (speaking, completed, stopped, error)
    ///   - progress: Optional progress value (0.0 to 1.0)
    ///   - errorMessage: Optional error message from backend
    public func handleTTSStatus(status: String, progress: Double?, errorMessage: String? = nil) {
        // Update progress if provided, clamped to valid range
        if let progress = progress {
            self.progress = max(0.0, min(1.0, progress))
        }

        // Notify delegate
        delegate?.ttsEngine(self, didUpdateStatus: status, progress: progress)

        // Update state based on status
        switch status {
        case "speaking":
            updateState(.speaking)
        case "completed":
            updateState(.idle)
            // Call completion callback
            onCompleteCallback?()
        case "stopped":
            updateState(.idle)
        case "error":
            updateState(.idle)
            let message = errorMessage ?? "Unknown TTS error"
            delegate?.ttsEngine(self, didEncounterError: .backendError(message))
        default:
            // Ignore unknown status values
            break
        }
    }

    // MARK: - IPC Message Processing

    /// Process incoming IPC message
    /// - Parameter message: The IPC message to process
    public func processIPCMessage(_ message: IPCMessage) {
        // Only handle tts_status messages
        guard message.type == .ttsStatus else {
            return
        }

        // Extract status from payload
        guard let statusValue = message.payload["status"]?.value as? String else {
            return
        }

        // Extract optional progress
        let progress = message.payload["progress"]?.value as? Double

        // Extract optional error message
        let errorMessage = message.payload["error"]?.value as? String

        // Handle the status
        handleTTSStatus(status: statusValue, progress: progress, errorMessage: errorMessage)
    }

    // MARK: - Private State Management

    /// Update state and notify observers
    private func updateState(_ newState: TTSState) {
        state = newState
        stateSubject.send(newState)
    }
}
