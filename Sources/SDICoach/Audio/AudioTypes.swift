import Foundation

// MARK: - Audio Source

/// Audio source identifier for captured audio
public enum AudioSource: String, Codable, Sendable {
    case microphone
    case system
}

// MARK: - Audio Buffer

/// Captured audio buffer containing PCM samples
public struct AudioBuffer: Sendable {
    /// PCM audio samples (Float32)
    public let samples: [Float]

    /// Sample rate of the audio data
    public let sampleRate: Int

    /// Timestamp when the audio was captured
    public let timestamp: Date

    /// Source of the audio (microphone or system)
    public let source: AudioSource

    public init(samples: [Float], sampleRate: Int, timestamp: Date, source: AudioSource) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.timestamp = timestamp
        self.source = source
    }
}

// MARK: - Capture Status

/// Status of audio capture
public enum CaptureStatus: String, Sendable {
    case inactive
    case active
    case error
}

// MARK: - Audio Capture Error

/// Errors that can occur during audio capture
public enum AudioCaptureError: Error, LocalizedError, Sendable, Equatable {
    /// Microphone permission was denied by the user
    case permissionDenied

    /// No microphone device is available
    case deviceNotAvailable

    /// Audio engine failed to start or capture
    case captureFailure(underlying: String)

    /// Already capturing - cannot start again
    case alreadyCapturing

    /// Not capturing - cannot stop
    case notCapturing

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .deviceNotAvailable:
            return "No microphone available"
        case .captureFailure(let message):
            return "Audio capture failed: \(message)"
        case .alreadyCapturing:
            return "Already capturing audio"
        case .notCapturing:
            return "Not currently capturing audio"
        }
    }
}

// MARK: - Audio Capture Delegate

/// Protocol for receiving audio capture callbacks
public protocol AudioCaptureDelegate: AnyObject, Sendable {
    /// Called when audio data is captured
    func didCaptureAudio(buffer: AudioBuffer, source: AudioSource)

    /// Called when an error occurs during capture
    func didEncounterError(error: AudioCaptureError)
}

// MARK: - Permission Status

/// Status of audio-related permissions
public struct PermissionStatus: Sendable {
    /// Screen capture permission (for system audio)
    public let screenCapture: Bool

    /// Microphone permission
    public let microphone: Bool

    public init(screenCapture: Bool, microphone: Bool) {
        self.screenCapture = screenCapture
        self.microphone = microphone
    }
}
