import Foundation
import AVFoundation

// MARK: - MicrophoneCapture

/// Microphone capture handler using AVAudioEngine
/// Captures microphone input (user's voice) and converts to mono PCM
public final class MicrophoneCapture: MicrophoneCaptureProtocol, @unchecked Sendable {

    // MARK: - Properties

    /// Delegate to receive audio capture callbacks (weak reference to avoid retain cycles)
    public weak var delegate: AudioCaptureDelegate?

    /// Thread-safe capturing state
    public private(set) var isCapturing: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isCapturing
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isCapturing = newValue
        }
    }
    private var _isCapturing: Bool = false

    /// Native capture sample rate (48kHz)
    public let captureSampleRate: Int = 48000

    /// Buffer size for audio capture
    private let bufferSize: UInt32 = 4096

    // MARK: - Dependencies

    private let audioEngine: AudioEngineProtocol
    private let permissionChecker: PermissionCheckerProtocol
    private var debugMode: Bool

    /// Lock for thread-safe state access
    private let lock = NSLock()

    // MARK: - Initialization

    /// Initialize with dependency injection for testability
    /// - Parameters:
    ///   - audioEngine: Audio engine protocol implementation
    ///   - permissionChecker: Permission checker protocol implementation
    ///   - debug: Enable debug logging
    public init(
        audioEngine: AudioEngineProtocol,
        permissionChecker: PermissionCheckerProtocol,
        debug: Bool = false
    ) {
        self.audioEngine = audioEngine
        self.permissionChecker = permissionChecker
        self.debugMode = debug
    }

    deinit {
        // Cleanup: stop capture if running
        lock.lock()
        let wasCapturing = _isCapturing
        _isCapturing = false
        lock.unlock()

        if wasCapturing {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }

    // MARK: - Debug

    public func setDebug(_ debug: Bool) {
        self.debugMode = debug
    }

    // MARK: - Permission

    public func checkPermission() -> Bool {
        let status = permissionChecker.authorizationStatus()
        return status == .authorized
    }

    public func requestPermission() async -> Bool {
        // Return true immediately if already authorized
        let status = permissionChecker.authorizationStatus()
        if status == .authorized {
            return true
        }
        // Request permission if not determined
        return await permissionChecker.requestAccess()
    }

    // MARK: - Capture Control

    public func startCapture() throws {
        lock.lock()
        defer { lock.unlock() }

        // Prevent double-start
        guard !_isCapturing else {
            if debugMode { print("[MIC] Already capturing") }
            return
        }

        // Check permission first
        let status = permissionChecker.authorizationStatus()
        guard status == .authorized else {
            if debugMode { print("[MIC] Permission denied") }
            throw AudioCaptureError.permissionDenied
        }

        // Get input format and verify device is available
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        if debugMode {
            print("[MIC] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels, valid: \(inputFormat.isValid)")
        }

        guard inputFormat.isValid else {
            if debugMode { print("[MIC] Invalid input format") }
            throw AudioCaptureError.deviceNotAvailable
        }

        // Install tap on input node to receive audio buffers
        if debugMode { print("[MIC] Installing tap...") }
        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputFormat
        ) { [weak self] bufferData in
            self?.processAudioBuffer(bufferData)
        }

        // Start the audio engine
        do {
            if debugMode { print("[MIC] Starting audio engine...") }
            try audioEngine.start()
            _isCapturing = true
            if debugMode { print("[MIC] Audio engine started, isRunning: \(audioEngine.isRunning)") }
        } catch {
            // Clean up tap on failure
            inputNode.removeTap(onBus: 0)
            if debugMode { print("[MIC] Failed to start: \(error)") }
            throw AudioCaptureError.captureFailure(underlying: error.localizedDescription)
        }
    }

    public func stopCapture() {
        lock.lock()
        defer { lock.unlock() }

        // Prevent stop when not capturing
        guard _isCapturing else {
            return
        }

        _isCapturing = false

        // Remove tap and stop engine
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        if debugMode { print("[MIC] Capture stopped") }
    }

    // MARK: - Internal (for testing)

    /// Simulate an error during capture (for testing)
    internal func simulateError(_ error: AudioCaptureError) {
        delegate?.didEncounterError(error: error)
    }

    // MARK: - Private Methods

    private func processAudioBuffer(_ bufferData: AudioBufferData) {
        // Handle empty buffer gracefully
        guard bufferData.frameLength > 0 else {
            return
        }

        // Convert to mono samples
        let monoSamples = convertToMono(bufferData)

        // Create AudioBuffer and notify delegate
        let audioBuffer = AudioBuffer(
            samples: monoSamples,
            sampleRate: Int(bufferData.sampleRate),
            timestamp: Date(),
            source: .microphone
        )

        delegate?.didCaptureAudio(buffer: audioBuffer, source: .microphone)
    }

    /// Convert multi-channel audio to mono by averaging channels
    private func convertToMono(_ bufferData: AudioBufferData) -> [Float] {
        let channelCount = Int(bufferData.channelCount)
        let frameLength = Int(bufferData.frameLength)

        // Guard against empty samples
        guard !bufferData.samples.isEmpty,
              !bufferData.samples[0].isEmpty else {
            return []
        }

        // If mono, return first channel directly
        if channelCount == 1 {
            return bufferData.samples[0]
        }

        // Multi-channel: average all channels
        var monoSamples = [Float](repeating: 0, count: frameLength)

        for i in 0..<frameLength {
            var sum: Float = 0
            for ch in 0..<channelCount {
                if ch < bufferData.samples.count && i < bufferData.samples[ch].count {
                    sum += bufferData.samples[ch][i]
                }
            }
            monoSamples[i] = sum / Float(channelCount)
        }

        return monoSamples
    }
}

// MARK: - AVFoundation Adapters

/// Adapter to wrap AVAudioEngine for protocol conformance
public final class AVAudioEngineAdapter: AudioEngineProtocol {
    private let engine: AVAudioEngine

    public init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
    }

    public func start() throws {
        try engine.start()
    }

    public func stop() {
        engine.stop()
    }

    public var isRunning: Bool {
        engine.isRunning
    }

    public var inputNode: AudioInputNodeProtocol {
        AVAudioInputNodeAdapter(node: engine.inputNode)
    }
}

/// Adapter to wrap AVAudioInputNode for protocol conformance
public final class AVAudioInputNodeAdapter: AudioInputNodeProtocol {
    private let node: AVAudioInputNode

    init(node: AVAudioInputNode) {
        self.node = node
    }

    public func outputFormat(forBus bus: Int) -> AudioFormatInfo {
        let format = node.outputFormat(forBus: bus)
        return AudioFormatInfo(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount
        )
    }

    public func installTap(
        onBus bus: Int,
        bufferSize: UInt32,
        format: AudioFormatInfo?,
        block: @escaping (AudioBufferData) -> Void
    ) {
        let avFormat: AVAudioFormat?
        if let format = format {
            avFormat = AVAudioFormat(
                standardFormatWithSampleRate: format.sampleRate,
                channels: format.channelCount
            )
        } else {
            avFormat = nil
        }

        node.installTap(onBus: bus, bufferSize: bufferSize, format: avFormat) { buffer, _ in
            guard let floatData = buffer.floatChannelData else { return }

            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)

            var samples: [[Float]] = []
            for ch in 0..<channelCount {
                var channelSamples = [Float](repeating: 0, count: frameCount)
                for i in 0..<frameCount {
                    channelSamples[i] = floatData[ch][i]
                }
                samples.append(channelSamples)
            }

            let bufferData = AudioBufferData(
                samples: samples,
                frameLength: buffer.frameLength,
                sampleRate: buffer.format.sampleRate,
                channelCount: UInt32(channelCount)
            )
            block(bufferData)
        }
    }

    public func removeTap(onBus bus: Int) {
        node.removeTap(onBus: bus)
    }
}

/// Adapter for AVCaptureDevice permission checking
public final class AVCaptureDevicePermissionChecker: PermissionCheckerProtocol {
    public init() {}

    public func authorizationStatus() -> PermissionAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    public func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - Convenience Initializer

extension MicrophoneCapture {
    /// Convenience initializer using real AVFoundation components
    /// Use this for production code
    public convenience init(debug: Bool = false) {
        self.init(
            audioEngine: AVAudioEngineAdapter(),
            permissionChecker: AVCaptureDevicePermissionChecker(),
            debug: debug
        )
    }
}
