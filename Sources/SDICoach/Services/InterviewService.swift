// InterviewService.swift
// Task 6.2.1, 6.2.2, 6.2.3: Interview session management via IPC
//
// Requirements from PRD.md:
// - Interview lifecycle (start, interviewing, end)
// - IPC message coordination with Backend
// - Feedback request and markdown saving

import Foundation

// MARK: - InterviewServiceError

/// Errors that can occur during interview service operations
public enum InterviewServiceError: Error, LocalizedError, Sendable, Equatable {
    case notConnected
    case alreadyInterviewing
    case notInterviewing
    case invalidQuestion
    case feedbackRequestFailed(String)
    case saveFeedbackFailed(String)
    case ipcError(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Interview service is not connected to backend"
        case .alreadyInterviewing:
            return "Interview is already in progress"
        case .notInterviewing:
            return "No interview is currently in progress"
        case .invalidQuestion:
            return "Invalid interview question provided"
        case .feedbackRequestFailed(let reason):
            return "Feedback request failed: \(reason)"
        case .saveFeedbackFailed(let reason):
            return "Failed to save feedback: \(reason)"
        case .ipcError(let reason):
            return "IPC error: \(reason)"
        }
    }
}

// MARK: - InterviewServiceDelegate

/// Protocol for receiving InterviewService callbacks
public protocol InterviewServiceDelegate: AnyObject, Sendable {
    /// Called when a new interview question is received from AI
    func interviewService(_ service: InterviewService, didReceiveQuestion question: String) async

    /// Called when a follow-up question is received from AI
    func interviewService(_ service: InterviewService, didReceiveFollowUp question: String) async

    /// Called when transcription is updated (partial or final)
    func interviewService(_ service: InterviewService, didUpdateTranscription text: String, isFinal: Bool) async

    /// Called when feedback is received from AI
    func interviewService(_ service: InterviewService, didReceiveFeedback markdown: String) async

    /// Called when interview session completes
    func interviewServiceDidComplete(_ service: InterviewService) async

    /// Called when a backend error is received
    func interviewService(_ service: InterviewService, didReceiveError error: String, message: String) async
}

// MARK: - IPCClientProtocol

/// Protocol for IPC client operations needed by InterviewService
/// This allows for dependency injection and testing with mock implementations
public protocol IPCClientProtocol: AnyObject, Sendable {
    /// Send an IPC message to the backend
    func send(_ message: IPCMessage) async throws

    /// Check if the client is connected
    func isConnected() async -> Bool

    /// Send a message and wait for response with timeout
    func sendAndWait(_ message: IPCMessage, timeout: TimeInterval) async throws -> IPCMessage
}

// MARK: - TTSEngineProtocol

/// Protocol for TTS Engine operations needed by InterviewService
public protocol TTSEngineProtocol: AnyObject, Sendable {
    /// Speak the given text
    func speak(text: String) async throws

    /// Stop current speech
    func stop() async throws

    /// Interrupt speech immediately
    func interrupt() async
}

// MARK: - InterviewService

/// Interview service that manages interview session lifecycle via IPC
///
/// Tasks:
/// - 6.2.1: Interview lifecycle (start, pause, resume, end)
/// - 6.2.2: IPC message coordination
/// - 6.2.3: Feedback request and markdown saving
public actor InterviewService {

    // MARK: - Constants

    /// Default timeout for feedback requests (in seconds)
    /// Feedback generation can take several minutes for longer interviews
    public static let defaultFeedbackTimeout: TimeInterval = 300.0

    /// Timeout for interview start request (in seconds)
    private static let interviewStartTimeout: TimeInterval = 180.0

    // MARK: - Properties

    /// Current interview session (nil when not interviewing)
    public private(set) var currentSession: InterviewSession?

    /// Whether an interview is currently in progress
    public var isInterviewing: Bool {
        currentSession != nil
    }

    /// Transcript manager for accumulating conversation
    public let transcriptManager: TranscriptManager

    /// IPC client for backend communication
    private let ipcClient: IPCClientProtocol

    /// TTS engine for speaking questions (optional)
    private let ttsEngine: TTSEngineProtocol?

    /// Delegate for receiving interview events
    private weak var delegate: InterviewServiceDelegate?

    /// Timeout for feedback requests (in seconds)
    private let feedbackTimeout: TimeInterval

    // MARK: - Initialization

    /// Initialize with dependencies
    /// - Parameters:
    ///   - ipcClient: Client for IPC communication with backend
    ///   - ttsEngine: Optional TTS engine for speaking questions
    ///   - feedbackTimeout: Timeout for feedback requests (defaults to 60 seconds)
    public init(
        ipcClient: IPCClientProtocol,
        ttsEngine: TTSEngineProtocol?,
        feedbackTimeout: TimeInterval = InterviewService.defaultFeedbackTimeout
    ) {
        self.ipcClient = ipcClient
        self.ttsEngine = ttsEngine
        self.feedbackTimeout = feedbackTimeout
        self.transcriptManager = TranscriptManager()
    }

    // MARK: - Delegate Management

    /// Set the delegate for interview events
    /// - Parameter delegate: The delegate to receive callbacks
    public func setDelegate(_ delegate: InterviewServiceDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Task 6.2.1: Interview Lifecycle

    /// Start a new interview session
    /// - Parameter question: The system design question for this interview
    /// - Throws: `InterviewServiceError` if unable to start
    public func startInterview(question: String) async throws {
        // Validate question is not empty or whitespace-only
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InterviewServiceError.invalidQuestion
        }

        // Check if already interviewing
        guard currentSession == nil else {
            throw InterviewServiceError.alreadyInterviewing
        }

        // Check IPC connection
        let connected = await ipcClient.isConnected()
        guard connected else {
            throw InterviewServiceError.notConnected
        }

        // Create new session
        currentSession = InterviewSession(question: question)

        // Send interview_start message and wait for response
        let startMessage = IPCMessage.interviewStart(question: question)
        let response = try await ipcClient.sendAndWait(startMessage, timeout: Self.interviewStartTimeout)

        // Check for error response
        if response.type == .error {
            let error = response.payload["error"]?.value as? String ?? "unknown_error"
            let errorMessage = response.payload["message"]?.value as? String ?? "Unknown error occurred"
            currentSession = nil  // Clear session on error
            throw InterviewServiceError.ipcError("\(error): \(errorMessage)")
        }

        // Process the response (should be interview_question)
        if response.type == .interviewQuestion,
           let questionText = response.payload["question"]?.value as? String {
            // Add interviewer question to transcript
            transcriptManager.add(source: .interviewer, content: questionText)

            // Notify delegate
            await delegate?.interviewService(self, didReceiveQuestion: questionText)

            // Speak via TTS if available
            // Note: TTS errors are intentionally ignored (try?) to not block the interview flow.
            // The interview can proceed without audio feedback if TTS fails.
            if let tts = ttsEngine {
                try? await tts.speak(text: questionText)
            }
        }
    }

    /// End the current interview session
    /// - Throws: `InterviewServiceError` if not interviewing
    public func endInterview() async throws {
        // Check if currently interviewing
        guard currentSession != nil else {
            throw InterviewServiceError.notInterviewing
        }

        // Stop TTS if speaking
        // Note: TTS errors are intentionally ignored to ensure interview end completes cleanly.
        if let tts = ttsEngine {
            try? await tts.stop()
        }

        // Send interview_end message
        let endMessage = IPCMessage.interviewEnd()
        try await ipcClient.send(endMessage)

        // Clear current session
        currentSession = nil

        // Notify delegate of completion
        await delegate?.interviewServiceDidComplete(self)
    }

    /// Pause the current interview session
    public func pauseInterview() async {
        // No-op if not interviewing
        guard currentSession != nil else {
            return
        }

        // Set session isPaused to true
        currentSession?.pause()

        // Stop TTS if speaking
        // Note: TTS errors are intentionally ignored to ensure pause completes smoothly.
        if let tts = ttsEngine {
            try? await tts.stop()
        }
    }

    /// Resume the current interview session
    public func resumeInterview() async {
        // No-op if not interviewing
        guard currentSession != nil else {
            return
        }

        // Set session isPaused to false
        currentSession?.resume()
    }

    // MARK: - Task 6.2.2: IPC Message Coordination

    /// Handle incoming IPC message from backend
    /// - Parameter message: The IPC message to process
    public func handleIPCMessage(_ message: IPCMessage) async {
        // Ignore messages when not interviewing (except for feedback messages)
        guard currentSession != nil else {
            return
        }

        switch message.type {
        case .interviewQuestion:
            // Process interview question
            if let questionText = message.payload["question"]?.value as? String {
                // Add to transcript
                transcriptManager.add(source: .interviewer, content: questionText)

                // Notify delegate
                await delegate?.interviewService(self, didReceiveQuestion: questionText)

                // Speak via TTS if available
                // Note: TTS errors are intentionally ignored to not block message processing.
                if let tts = ttsEngine {
                    try? await tts.speak(text: questionText)
                }
            }

        case .interviewFollowup:
            // Process follow-up question
            if let questionText = message.payload["question"]?.value as? String {
                // Increment follow-up count
                currentSession?.incrementFollowUp()

                // Add to transcript
                transcriptManager.add(source: .interviewer, content: questionText)

                // Notify delegate
                await delegate?.interviewService(self, didReceiveFollowUp: questionText)

                // Speak via TTS if available
                // Note: TTS errors are intentionally ignored to not block message processing.
                if let tts = ttsEngine {
                    try? await tts.speak(text: questionText)
                }
            }

        case .transcription:
            // Process transcription (partial or final)
            if let text = message.payload["text"]?.value as? String,
               let isFinal = message.payload["is_final"]?.value as? Bool {
                // Notify delegate of transcription update
                await delegate?.interviewService(self, didUpdateTranscription: text, isFinal: isFinal)

                // Only add final transcriptions to transcript manager
                if isFinal {
                    transcriptManager.add(source: .user, content: text)
                }
            }

        case .feedbackResponse:
            // Process feedback response
            if let markdown = message.payload["markdown"]?.value as? String {
                await delegate?.interviewService(self, didReceiveFeedback: markdown)
            }

        case .error:
            // Process backend error
            if let error = message.payload["error"]?.value as? String,
               let errorMessage = message.payload["message"]?.value as? String {
                await delegate?.interviewService(self, didReceiveError: error, message: errorMessage)
            }

        default:
            // Ignore other message types
            break
        }
    }

    /// Send user's response to the backend
    /// - Parameter response: The transcribed user response
    /// - Throws: `InterviewServiceError` if not interviewing
    public func sendUserResponse(_ response: String) async throws {
        // Check if currently interviewing
        guard currentSession != nil else {
            throw InterviewServiceError.notInterviewing
        }

        // Interrupt TTS if speaking
        if let tts = ttsEngine {
            await tts.interrupt()
        }

        // Add response to transcript manager
        transcriptManager.add(source: .user, content: response)

        // Send interview_response message
        let responseMessage = IPCMessage.interviewResponse(response: response)
        try await ipcClient.send(responseMessage)
    }

    // MARK: - Task 6.2.3: Feedback Request and Saving

    /// Request feedback from the AI based on conversation transcript
    /// - Returns: Markdown formatted feedback
    /// - Throws: `InterviewServiceError` if request fails
    public func requestFeedback() async throws -> String {
        // Check if currently interviewing
        guard currentSession != nil else {
            throw InterviewServiceError.notInterviewing
        }

        // Format transcript for feedback request
        let formattedTranscript = transcriptManager.toFormattedTranscript(for: true)

        // Send feedback_request message
        let feedbackRequest = IPCMessage.feedbackRequest(transcript: formattedTranscript)
        let response = try await ipcClient.sendAndWait(feedbackRequest, timeout: feedbackTimeout)

        // Check for error response
        if response.type == .error {
            let error = response.payload["error"]?.value as? String ?? "unknown_error"
            let errorMessage = response.payload["message"]?.value as? String ?? "Unknown error occurred"
            throw InterviewServiceError.feedbackRequestFailed("\(error): \(errorMessage)")
        }

        // Extract markdown from response
        guard response.type == .feedbackResponse,
              let markdown = response.payload["markdown"]?.value as? String else {
            throw InterviewServiceError.feedbackRequestFailed("Invalid response from server")
        }

        return markdown
    }

    /// Save feedback markdown to a file
    /// - Parameters:
    ///   - markdown: The feedback content to save
    ///   - path: The file path to save to
    /// - Throws: `InterviewServiceError.saveFeedbackFailed` if unable to save
    public func saveFeedback(_ markdown: String, to path: String) async throws {
        do {
            try markdown.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw InterviewServiceError.saveFeedbackFailed(error.localizedDescription)
        }
    }
}
