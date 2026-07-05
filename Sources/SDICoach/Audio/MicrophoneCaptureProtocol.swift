import Foundation

// MARK: - Microphone Capture Protocol

/// Protocol defining the interface for microphone capture
/// This allows for dependency injection and testing with mock implementations
public protocol MicrophoneCaptureProtocol: AnyObject, Sendable {
    /// Delegate to receive audio capture callbacks
    var delegate: AudioCaptureDelegate? { get set }

    /// Whether the capture is currently active
    var isCapturing: Bool { get }

    /// The sample rate used for capturing audio (native device rate)
    var captureSampleRate: Int { get }

    /// Check if microphone permission is currently granted
    func checkPermission() -> Bool

    /// Request microphone permission from the user
    /// - Returns: true if permission was granted
    func requestPermission() async -> Bool

    /// Start capturing audio from the microphone
    /// - Throws: AudioCaptureError if capture cannot be started
    func startCapture() throws

    /// Stop capturing audio from the microphone
    func stopCapture()

    /// Set debug mode for verbose logging
    func setDebug(_ debug: Bool)
}

// MARK: - Audio Engine Protocol

/// Protocol for audio engine operations (for dependency injection)
/// This abstracts AVAudioEngine for testability
public protocol AudioEngineProtocol: AnyObject {
    /// Start the audio engine
    func start() throws

    /// Stop the audio engine
    func stop()

    /// Check if the engine is running
    var isRunning: Bool { get }

    /// Get the input node for microphone capture
    var inputNode: AudioInputNodeProtocol { get }
}

// MARK: - Audio Input Node Protocol

/// Protocol for audio input node operations
public protocol AudioInputNodeProtocol: AnyObject {
    /// Get the output format for the specified bus
    func outputFormat(forBus bus: Int) -> AudioFormatInfo

    /// Install a tap on the input node to receive audio buffers
    func installTap(
        onBus bus: Int,
        bufferSize: UInt32,
        format: AudioFormatInfo?,
        block: @escaping (AudioBufferData) -> Void
    )

    /// Remove the tap from the input node
    func removeTap(onBus bus: Int)
}

// MARK: - Audio Format Info

/// Simplified audio format information
public struct AudioFormatInfo: Sendable {
    public let sampleRate: Double
    public let channelCount: UInt32

    public init(sampleRate: Double, channelCount: UInt32) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    /// Check if the format is valid (non-zero sample rate)
    public var isValid: Bool {
        sampleRate > 0
    }
}

// MARK: - Audio Buffer Data

/// Raw audio buffer data for processing
public struct AudioBufferData: Sendable {
    public let samples: [[Float]]  // Channel data
    public let frameLength: UInt32
    public let sampleRate: Double
    public let channelCount: UInt32

    public init(samples: [[Float]], frameLength: UInt32, sampleRate: Double, channelCount: UInt32) {
        self.samples = samples
        self.frameLength = frameLength
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

// MARK: - Permission Checker Protocol

/// Protocol for checking and requesting audio permissions
public protocol PermissionCheckerProtocol: Sendable {
    /// Check current authorization status
    func authorizationStatus() -> PermissionAuthorizationStatus

    /// Request access to audio
    func requestAccess() async -> Bool
}

/// Authorization status for audio permissions
public enum PermissionAuthorizationStatus: Sendable {
    case notDetermined
    case denied
    case authorized
    case restricted
}
