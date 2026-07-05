// Constants.swift
// Centralized constants for the sdi.coach application
//
// This file consolidates magic numbers and configuration values
// to improve maintainability and readability.

import Foundation

// MARK: - Application Constants

/// Centralized constants for the sdi.coach application
public enum Constants {

    // MARK: - Timing Constants

    /// Timing-related constants
    public enum Timing {
        /// Spinner frame duration in nanoseconds (80ms)
        public static let spinnerFrameNanoseconds: UInt64 = 80_000_000

        /// Timer tick interval in nanoseconds (1 second)
        public static let timerTickNanoseconds: UInt64 = 1_000_000_000

        /// Spinner frame duration as TimeInterval (for reference)
        public static let spinnerFrameSeconds: TimeInterval = 0.08
    }

    // MARK: - Transcript Constants

    /// Transcript display-related constants
    public enum Transcript {
        /// Seconds before starting a new transcript line (aggregation interval)
        public static let headerIntervalSeconds: TimeInterval = 7.0
    }

    // MARK: - IPC Constants

    /// IPC communication-related constants
    public enum IPC {
        /// Default socket path for Unix domain socket
        public static let defaultSocketPath = "/tmp/sdicoach.sock"

        /// Default timeout for IPC operations (seconds)
        public static let defaultTimeoutSeconds: TimeInterval = 180.0

        /// Timeout for feedback generation (seconds)
        public static let feedbackTimeoutSeconds: TimeInterval = 300.0

        /// Timeout for interview start request (seconds)
        public static let interviewStartTimeoutSeconds: TimeInterval = 180.0
    }

    // MARK: - Audio Constants

    /// Audio processing-related constants
    public enum Audio {
        /// Input sample rate from microphone (Hz)
        public static let inputSampleRate: Int = 48000

        /// Output sample rate for MLX-Whisper (Hz)
        public static let outputSampleRate: Int = 16000

        /// Maximum Int16 value for audio normalization
        public static let maxInt16Value: Float = 32767.0
    }

    // MARK: - Interview Constants

    /// Interview session-related constants
    public enum Interview {
        /// Default interview duration in seconds (30 minutes)
        public static let defaultDurationSeconds: Int = 1800

        /// Default interview duration in minutes
        public static let defaultDurationMinutes: Int = 30
    }

    // MARK: - Reconnection Constants

    /// Reconnection behavior constants
    public enum Reconnection {
        /// Initial delay before first reconnection attempt (seconds)
        public static let initialDelaySeconds: TimeInterval = 1.0

        /// Maximum delay between reconnection attempts (seconds)
        public static let maxDelaySeconds: TimeInterval = 10.0

        /// Multiplier for exponential backoff
        public static let backoffMultiplier: Double = 2.0

        /// Maximum number of reconnection attempts
        public static let maxRetries: Int = 3
    }
}
