// InterviewSession.swift
// Task 6.1.1: InterviewSession state management
//
// Type definition from PRD.md:
// - Manages interview session state including question, time, transcripts, and pause state
// - Provides computed properties for time formatting and progress tracking

import Foundation

/// Interview session state management
/// Tracks question, time remaining, transcripts, follow-up count, and pause state
public struct InterviewSession: Sendable, Codable {
    // MARK: - Stored Properties

    /// The interview question for this session
    public let question: String

    /// When the session started
    public let startTime: Date

    /// Transcript entries for this session
    public var transcripts: [TranscriptEntry]

    /// Number of follow-up questions asked on current topic
    public var followUpCount: Int

    /// Whether the session is currently paused
    public var isPaused: Bool

    /// Time remaining in seconds (default: 30 minutes = 1800 seconds)
    public var remainingSeconds: Int

    // MARK: - Constants

    /// Total interview duration in seconds (30 minutes)
    private static let defaultDurationSeconds = 1800

    // MARK: - Initialization

    /// Initialize a new interview session with the given question
    /// - Parameter question: The interview question
    public init(question: String) {
        self.question = question
        self.startTime = Date()
        self.transcripts = []
        self.followUpCount = 0
        self.isPaused = false
        self.remainingSeconds = Self.defaultDurationSeconds
    }

    // MARK: - Transcript Management

    /// Add a transcript entry with automatic timestamp
    /// - Parameters:
    ///   - source: The source of the transcript (.interviewer or .user)
    ///   - content: The text content of the transcript
    public mutating func addTranscript(source: TranscriptSource, content: String) {
        let entry = TranscriptEntry(source: source, content: content, timestamp: Date())
        transcripts.append(entry)
    }

    // MARK: - Pause/Resume

    /// Pause the interview session
    public mutating func pause() {
        isPaused = true
    }

    /// Resume the interview session
    public mutating func resume() {
        isPaused = false
    }

    // MARK: - Follow-up Management

    /// Increment the follow-up count by 1
    public mutating func incrementFollowUp() {
        followUpCount += 1
    }

    /// Reset the follow-up count to 0
    public mutating func resetFollowUp() {
        followUpCount = 0
    }

    // MARK: - Time Management

    /// Decrement remaining time by specified seconds (minimum 0)
    /// - Parameter seconds: Number of seconds to subtract
    public mutating func decrementTime(by seconds: Int) {
        remainingSeconds = max(0, remainingSeconds - seconds)
    }

    // MARK: - Computed Properties

    /// Returns true if remaining time is zero
    public var isTimeUp: Bool {
        remainingSeconds == 0
    }

    /// Returns remaining time formatted as "MM:SS"
    public var formattedRemainingTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Returns elapsed time in seconds
    public var elapsedSeconds: Int {
        Self.defaultDurationSeconds - remainingSeconds
    }

    /// Returns total duration in seconds (constant 1800)
    public var totalDurationSeconds: Int {
        Self.defaultDurationSeconds
    }

    /// Returns progress percentage (0.0 to 100.0)
    public var progressPercentage: Double {
        Double(elapsedSeconds) / Double(totalDurationSeconds) * 100.0
    }
}
