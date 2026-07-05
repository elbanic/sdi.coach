import Testing
import Foundation
@testable import SDICoach

// MARK: - Mock Types for Testing

/// Mock audio engine for testing without actual hardware
final class MockAudioEngine: AudioEngineProtocol, @unchecked Sendable {
    private let lock = NSLock()

    private var _isRunning = false
    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    private var _inputNodeMock: MockAudioInputNode
    var inputNode: AudioInputNodeProtocol {
        lock.lock()
        defer { lock.unlock() }
        return _inputNodeMock
    }

    var startCallCount = 0
    var stopCallCount = 0
    var shouldThrowOnStart = false
    var startError: Error?

    init(inputFormat: AudioFormatInfo = AudioFormatInfo(sampleRate: 48000, channelCount: 1)) {
        _inputNodeMock = MockAudioInputNode(outputFormat: inputFormat)
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }

        startCallCount += 1

        if shouldThrowOnStart {
            throw startError ?? NSError(domain: "MockAudioEngine", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Mock engine start failure"
            ])
        }

        _isRunning = true
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        stopCallCount += 1
        _isRunning = false
    }

    /// Simulate audio buffer callback
    func simulateAudioBuffer(_ buffer: AudioBufferData) {
        lock.lock()
        let inputNode = _inputNodeMock
        lock.unlock()
        inputNode.simulateBuffer(buffer)
    }
}

/// Mock audio input node for testing
final class MockAudioInputNode: AudioInputNodeProtocol, @unchecked Sendable {
    private let lock = NSLock()

    private var _outputFormat: AudioFormatInfo
    private var _tapInstalled = false
    private var _tapBlock: ((AudioBufferData) -> Void)?

    var installTapCallCount = 0
    var removeTapCallCount = 0

    init(outputFormat: AudioFormatInfo) {
        _outputFormat = outputFormat
    }

    func outputFormat(forBus bus: Int) -> AudioFormatInfo {
        lock.lock()
        defer { lock.unlock() }
        return _outputFormat
    }

    func installTap(
        onBus bus: Int,
        bufferSize: UInt32,
        format: AudioFormatInfo?,
        block: @escaping (AudioBufferData) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        installTapCallCount += 1
        _tapInstalled = true
        _tapBlock = block
    }

    func removeTap(onBus bus: Int) {
        lock.lock()
        defer { lock.unlock() }

        removeTapCallCount += 1
        _tapInstalled = false
        _tapBlock = nil
    }

    var isTapInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _tapInstalled
    }

    func simulateBuffer(_ buffer: AudioBufferData) {
        lock.lock()
        let block = _tapBlock
        lock.unlock()
        block?(buffer)
    }

    func setOutputFormat(_ format: AudioFormatInfo) {
        lock.lock()
        defer { lock.unlock() }
        _outputFormat = format
    }
}

/// Mock permission checker for testing
final class MockPermissionChecker: PermissionCheckerProtocol, @unchecked Sendable {
    private let lock = NSLock()

    private var _status: PermissionAuthorizationStatus = .notDetermined
    private var _grantOnRequest = true

    var requestAccessCallCount = 0

    func authorizationStatus() -> PermissionAuthorizationStatus {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    func requestAccess() async -> Bool {
        lock.lock()
        requestAccessCallCount += 1
        let shouldGrant = _grantOnRequest

        if shouldGrant {
            _status = .authorized
        } else {
            _status = .denied
        }
        lock.unlock()

        return shouldGrant
    }

    func setStatus(_ status: PermissionAuthorizationStatus) {
        lock.lock()
        defer { lock.unlock() }
        _status = status
    }

    func setGrantOnRequest(_ grant: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _grantOnRequest = grant
    }
}

/// Mock delegate for capturing audio callbacks
final class MockAudioCaptureDelegate: AudioCaptureDelegate, @unchecked Sendable {
    private let lock = NSLock()

    private var _capturedBuffers: [AudioBuffer] = []
    private var _capturedErrors: [AudioCaptureError] = []

    var capturedBuffers: [AudioBuffer] {
        lock.lock()
        defer { lock.unlock() }
        return _capturedBuffers
    }

    var capturedErrors: [AudioCaptureError] {
        lock.lock()
        defer { lock.unlock() }
        return _capturedErrors
    }

    func didCaptureAudio(buffer: AudioBuffer, source: AudioSource) {
        lock.lock()
        defer { lock.unlock() }
        _capturedBuffers.append(buffer)
    }

    func didEncounterError(error: AudioCaptureError) {
        lock.lock()
        defer { lock.unlock() }
        _capturedErrors.append(error)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _capturedBuffers.removeAll()
        _capturedErrors.removeAll()
    }
}

// MARK: - Test Suite: 2.1.1 AVAudioEngine Initialization

@Suite("MicrophoneCapture: AVAudioEngine Initialization")
struct MicrophoneCaptureInitializationTests {

    @Test("Engine starts correctly when permission is granted")
    func engineStartsCorrectly() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act
        try capture.startCapture()

        // Assert
        #expect(mockEngine.isRunning == true)
        #expect(mockEngine.startCallCount == 1)
        #expect(capture.isCapturing == true)
    }

    @Test("Engine stops correctly after start")
    func engineStopsCorrectly() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act
        try capture.startCapture()
        capture.stopCapture()

        // Assert
        #expect(mockEngine.isRunning == false)
        #expect(mockEngine.stopCallCount == 1)
        #expect(capture.isCapturing == false)
    }

    @Test("Proper cleanup on deinit")
    func cleanupOnDeinit() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        var capture: MicrophoneCapture? = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act
        try capture?.startCapture()
        #expect(mockEngine.isRunning == true)

        capture = nil  // Trigger deinit

        // Assert - engine should be stopped after deinit
        #expect(mockEngine.isRunning == false)
        #expect(mockEngine.stopCallCount == 1)
    }

    @Test("Default sample rate is 48kHz")
    func defaultSampleRate() {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Assert
        #expect(capture.captureSampleRate == 48000)
    }

    @Test("Debug mode can be toggled")
    func debugModeToggle() {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission,
            debug: false
        )

        // Act & Assert - should not crash
        capture.setDebug(true)
        capture.setDebug(false)
    }
}

// MARK: - Test Suite: 2.1.2 PCM Buffer Continuous Capture

@Suite("MicrophoneCapture: PCM Buffer Capture")
struct MicrophoneCapturePCMBufferTests {

    @Test("Captures audio at correct sample rate (48kHz native)")
    func capturesAtCorrectSampleRate() throws {
        // Arrange
        let mockEngine = MockAudioEngine(
            inputFormat: AudioFormatInfo(sampleRate: 48000, channelCount: 1)
        )
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        try capture.startCapture()

        // Simulate audio buffer at 48kHz
        let testSamples: [[Float]] = [[0.1, 0.2, 0.3, 0.4]]
        let bufferData = AudioBufferData(
            samples: testSamples,
            frameLength: 4,
            sampleRate: 48000,
            channelCount: 1
        )
        mockEngine.simulateAudioBuffer(bufferData)

        // Assert
        #expect(mockDelegate.capturedBuffers.count == 1)
        #expect(mockDelegate.capturedBuffers.first?.sampleRate == 48000)
    }

    @Test("Buffer callback is invoked with audio data")
    func bufferCallbackInvoked() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        try capture.startCapture()

        let testSamples: [[Float]] = [[0.5, -0.5, 0.25, -0.25]]
        mockEngine.simulateAudioBuffer(AudioBufferData(
            samples: testSamples,
            frameLength: 4,
            sampleRate: 48000,
            channelCount: 1
        ))

        // Assert
        #expect(mockDelegate.capturedBuffers.count == 1)

        let capturedBuffer = mockDelegate.capturedBuffers.first!
        #expect(capturedBuffer.samples.count == 4)
        #expect(capturedBuffer.source == .microphone)
    }

    @Test("Multiple buffers are captured sequentially")
    func multipleBuffersCaptured() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        try capture.startCapture()

        // Simulate 3 audio buffers
        for i in 0..<3 {
            let samples: [[Float]] = [[Float(i) * 0.1]]
            mockEngine.simulateAudioBuffer(AudioBufferData(
                samples: samples,
                frameLength: 1,
                sampleRate: 48000,
                channelCount: 1
            ))
        }

        // Assert
        #expect(mockDelegate.capturedBuffers.count == 3)
    }

    @Test("Mono conversion from stereo input - averages channels")
    func monoConversionFromStereo() throws {
        // Arrange
        let mockEngine = MockAudioEngine(
            inputFormat: AudioFormatInfo(sampleRate: 48000, channelCount: 2)
        )
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        try capture.startCapture()

        // Stereo input: left = [0.4, 0.8], right = [0.6, 0.2]
        // Expected mono: [(0.4+0.6)/2, (0.8+0.2)/2] = [0.5, 0.5]
        let stereoSamples: [[Float]] = [
            [0.4, 0.8],  // Left channel
            [0.6, 0.2]   // Right channel
        ]
        mockEngine.simulateAudioBuffer(AudioBufferData(
            samples: stereoSamples,
            frameLength: 2,
            sampleRate: 48000,
            channelCount: 2
        ))

        // Assert
        #expect(mockDelegate.capturedBuffers.count == 1)

        let capturedBuffer = mockDelegate.capturedBuffers.first!
        #expect(capturedBuffer.samples.count == 2)

        // Check mono conversion (average of stereo channels)
        #expect(abs(capturedBuffer.samples[0] - 0.5) < 0.001)
        #expect(abs(capturedBuffer.samples[1] - 0.5) < 0.001)
    }

    @Test("Mono input passes through unchanged")
    func monoInputPassthrough() throws {
        // Arrange
        let mockEngine = MockAudioEngine(
            inputFormat: AudioFormatInfo(sampleRate: 48000, channelCount: 1)
        )
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        try capture.startCapture()

        let monoSamples: [[Float]] = [[0.1, 0.2, 0.3]]
        mockEngine.simulateAudioBuffer(AudioBufferData(
            samples: monoSamples,
            frameLength: 3,
            sampleRate: 48000,
            channelCount: 1
        ))

        // Assert
        let capturedBuffer = mockDelegate.capturedBuffers.first!
        #expect(capturedBuffer.samples == [0.1, 0.2, 0.3])
    }

    @Test("Timestamp is set on captured buffer")
    func timestampIsSet() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        let beforeCapture = Date()
        try capture.startCapture()

        mockEngine.simulateAudioBuffer(AudioBufferData(
            samples: [[0.1]],
            frameLength: 1,
            sampleRate: 48000,
            channelCount: 1
        ))

        let afterCapture = Date()

        // Assert
        let capturedBuffer = mockDelegate.capturedBuffers.first!
        #expect(capturedBuffer.timestamp >= beforeCapture)
        #expect(capturedBuffer.timestamp <= afterCapture)
    }

    @Test("Empty buffer is handled gracefully")
    func emptyBufferHandled() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        try capture.startCapture()

        // Simulate empty buffer
        mockEngine.simulateAudioBuffer(AudioBufferData(
            samples: [[]],
            frameLength: 0,
            sampleRate: 48000,
            channelCount: 1
        ))

        // Assert - should either skip or capture empty buffer without crashing
        // The implementation decides which behavior is appropriate
        #expect(mockDelegate.capturedErrors.isEmpty)
    }
}

// MARK: - Test Suite: 2.1.3 Audio Session Management

@Suite("MicrophoneCapture: State Transitions")
struct MicrophoneCaptureStateTests {

    @Test("Prevents double-start - second start is no-op")
    func preventsDoubleStart() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act
        try capture.startCapture()
        try capture.startCapture()  // Second start

        // Assert - engine.start() should only be called once
        #expect(mockEngine.startCallCount == 1)
        #expect(capture.isCapturing == true)
    }

    @Test("Prevents double-stop - second stop is no-op")
    func preventsDoubleStop() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act
        try capture.startCapture()
        capture.stopCapture()
        capture.stopCapture()  // Second stop

        // Assert - engine.stop() should only be called once
        #expect(mockEngine.stopCallCount == 1)
        #expect(capture.isCapturing == false)
    }

    @Test("Stop when not started is no-op")
    func stopWhenNotStarted() {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act
        capture.stopCapture()

        // Assert
        #expect(mockEngine.stopCallCount == 0)
        #expect(capture.isCapturing == false)
    }

    @Test("Can restart after stop")
    func canRestartAfterStop() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act
        try capture.startCapture()
        capture.stopCapture()
        try capture.startCapture()

        // Assert
        #expect(mockEngine.startCallCount == 2)
        #expect(mockEngine.stopCallCount == 1)
        #expect(capture.isCapturing == true)
    }

    @Test("isCapturing reflects actual state")
    func isCapturingReflectsState() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Assert initial state
        #expect(capture.isCapturing == false)

        // Act & Assert after start
        try capture.startCapture()
        #expect(capture.isCapturing == true)

        // Act & Assert after stop
        capture.stopCapture()
        #expect(capture.isCapturing == false)
    }

    @Test("Tap is installed on start and removed on stop")
    func tapManagement() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        let inputNode = mockEngine.inputNode as! MockAudioInputNode

        // Assert initial state
        #expect(inputNode.isTapInstalled == false)

        // Act & Assert after start
        try capture.startCapture()
        #expect(inputNode.installTapCallCount == 1)
        #expect(inputNode.isTapInstalled == true)

        // Act & Assert after stop
        capture.stopCapture()
        #expect(inputNode.removeTapCallCount == 1)
        #expect(inputNode.isTapInstalled == false)
    }
}

// MARK: - Test Suite: 2.1.4 Error Handling

@Suite("MicrophoneCapture: Error Handling")
struct MicrophoneCaptureErrorTests {

    @Test("Throws permissionDenied when permission not granted")
    func throwsPermissionDenied() {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.denied)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act & Assert
        #expect(throws: AudioCaptureError.self) {
            try capture.startCapture()
        }

        // Verify specific error
        do {
            try capture.startCapture()
        } catch let error as AudioCaptureError {
            if case .permissionDenied = error {
                // Expected
            } else {
                Issue.record("Expected permissionDenied error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Throws deviceNotAvailable when no microphone")
    func throwsDeviceNotAvailable() {
        // Arrange - simulate no device by setting sample rate to 0
        let mockEngine = MockAudioEngine(
            inputFormat: AudioFormatInfo(sampleRate: 0, channelCount: 0)
        )
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act & Assert
        #expect(throws: AudioCaptureError.self) {
            try capture.startCapture()
        }

        do {
            try capture.startCapture()
        } catch let error as AudioCaptureError {
            if case .deviceNotAvailable = error {
                // Expected
            } else {
                Issue.record("Expected deviceNotAvailable error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Throws captureFailure when engine fails to start")
    func throwsCaptureFailure() {
        // Arrange
        let mockEngine = MockAudioEngine()
        mockEngine.shouldThrowOnStart = true
        mockEngine.startError = NSError(
            domain: "AVAudioEngine",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Hardware error"]
        )

        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act & Assert
        #expect(throws: AudioCaptureError.self) {
            try capture.startCapture()
        }

        do {
            try capture.startCapture()
        } catch let error as AudioCaptureError {
            if case .captureFailure = error {
                // Expected
            } else {
                Issue.record("Expected captureFailure error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Cleans up tap on engine start failure")
    func cleansUpOnFailure() {
        // Arrange
        let mockEngine = MockAudioEngine()
        mockEngine.shouldThrowOnStart = true

        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        let inputNode = mockEngine.inputNode as! MockAudioInputNode

        // Act
        do {
            try capture.startCapture()
        } catch {
            // Expected to throw
        }

        // Assert - tap should be removed after failure
        #expect(inputNode.isTapInstalled == false)
        #expect(capture.isCapturing == false)
    }

    @Test("Handles restricted permission status")
    func handlesRestrictedPermission() {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.restricted)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act & Assert
        #expect(throws: AudioCaptureError.permissionDenied) {
            try capture.startCapture()
        }
    }

    @Test("Delegate receives error on capture failure during streaming")
    func delegateReceivesStreamingError() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        try capture.startCapture()

        // Simulate an error during capture (implementation-specific)
        capture.simulateError(.captureFailure(underlying: "Stream interrupted"))

        // Assert
        #expect(mockDelegate.capturedErrors.count == 1)
        if case .captureFailure(let message) = mockDelegate.capturedErrors.first {
            #expect(message.contains("interrupted"))
        } else {
            Issue.record("Expected captureFailure error")
        }
    }
}

// MARK: - Test Suite: Permission Checking

@Suite("MicrophoneCapture: Permission Checking")
struct MicrophoneCapturePermissionTests {

    @Test("checkPermission returns true when authorized")
    func checkPermissionAuthorized() {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act & Assert
        #expect(capture.checkPermission() == true)
    }

    @Test("checkPermission returns false when denied")
    func checkPermissionDenied() {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.denied)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act & Assert
        #expect(capture.checkPermission() == false)
    }

    @Test("checkPermission returns false when not determined")
    func checkPermissionNotDetermined() {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.notDetermined)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act & Assert
        #expect(capture.checkPermission() == false)
    }

    @Test("requestPermission triggers permission request")
    func requestPermissionTriggersRequest() async {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.notDetermined)
        mockPermission.setGrantOnRequest(true)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act
        let result = await capture.requestPermission()

        // Assert
        #expect(result == true)
        #expect(mockPermission.requestAccessCallCount == 1)
    }

    @Test("requestPermission returns false when user denies")
    func requestPermissionDenied() async {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.notDetermined)
        mockPermission.setGrantOnRequest(false)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act
        let result = await capture.requestPermission()

        // Assert
        #expect(result == false)
    }

    @Test("requestPermission returns true immediately if already authorized")
    func requestPermissionAlreadyAuthorized() async {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act
        let result = await capture.requestPermission()

        // Assert
        #expect(result == true)
        // Should not trigger new request if already authorized
        #expect(mockPermission.requestAccessCallCount == 0)
    }
}

// MARK: - Test Suite: Edge Cases

@Suite("MicrophoneCapture: Edge Cases")
struct MicrophoneCaptureEdgeCaseTests {

    @Test("Handles very large buffer sizes")
    func handlesLargeBuffers() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        try capture.startCapture()

        // Large buffer (100k samples)
        let largeSamples = [Float](repeating: 0.5, count: 100_000)
        mockEngine.simulateAudioBuffer(AudioBufferData(
            samples: [largeSamples],
            frameLength: 100_000,
            sampleRate: 48000,
            channelCount: 1
        ))

        // Assert
        #expect(mockDelegate.capturedBuffers.count == 1)
        #expect(mockDelegate.capturedBuffers.first?.samples.count == 100_000)
    }

    @Test("Handles rapid start/stop cycles")
    func handlesRapidStartStop() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act - rapid cycling
        for _ in 0..<10 {
            try capture.startCapture()
            capture.stopCapture()
        }

        // Assert - should handle without crashes or leaks
        #expect(mockEngine.startCallCount == 10)
        #expect(mockEngine.stopCallCount == 10)
        #expect(capture.isCapturing == false)
    }

    @Test("Handles audio samples at boundary values")
    func handlesBoundaryValues() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        try capture.startCapture()

        // Boundary values for audio samples
        let boundarySamples: [[Float]] = [[
            -1.0,      // Minimum
            1.0,       // Maximum
            0.0,       // Zero
            Float.leastNormalMagnitude,
            -Float.leastNormalMagnitude
        ]]
        mockEngine.simulateAudioBuffer(AudioBufferData(
            samples: boundarySamples,
            frameLength: 5,
            sampleRate: 48000,
            channelCount: 1
        ))

        // Assert
        let captured = mockDelegate.capturedBuffers.first!
        #expect(captured.samples[0] == -1.0)
        #expect(captured.samples[1] == 1.0)
        #expect(captured.samples[2] == 0.0)
    }

    @Test("No delegate does not crash")
    func noDelegateNoCrash() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        // Note: No delegate set

        // Act
        try capture.startCapture()

        mockEngine.simulateAudioBuffer(AudioBufferData(
            samples: [[0.1, 0.2]],
            frameLength: 2,
            sampleRate: 48000,
            channelCount: 1
        ))

        capture.stopCapture()

        // Assert - should complete without crash
        #expect(capture.isCapturing == false)
    }

    @Test("Weak delegate reference does not retain")
    func weakDelegateReference() throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        var delegateRef: MockAudioCaptureDelegate? = MockAudioCaptureDelegate()
        capture.delegate = delegateRef

        // Act - release delegate
        delegateRef = nil

        try capture.startCapture()
        mockEngine.simulateAudioBuffer(AudioBufferData(
            samples: [[0.1]],
            frameLength: 1,
            sampleRate: 48000,
            channelCount: 1
        ))

        // Assert - should not crash when delegate is nil
        #expect(capture.delegate == nil)
    }

    @Test("Handles unusual channel counts")
    func handlesUnusualChannelCounts() throws {
        // Arrange - 6 channel surround sound input
        let mockEngine = MockAudioEngine(
            inputFormat: AudioFormatInfo(sampleRate: 48000, channelCount: 6)
        )
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        // Act
        try capture.startCapture()

        // 6 channels with value 0.6 each -> average = 0.6
        let multiChannelSamples: [[Float]] = [
            [0.6], [0.6], [0.6], [0.6], [0.6], [0.6]
        ]
        mockEngine.simulateAudioBuffer(AudioBufferData(
            samples: multiChannelSamples,
            frameLength: 1,
            sampleRate: 48000,
            channelCount: 6
        ))

        // Assert - should convert to mono
        let captured = mockDelegate.capturedBuffers.first!
        #expect(captured.samples.count == 1)
        #expect(abs(captured.samples[0] - 0.6) < 0.001)
    }
}

// MARK: - Test Suite: Thread Safety

@Suite("MicrophoneCapture: Thread Safety")
struct MicrophoneCaptureThreadSafetyTests {

    @Test("Concurrent buffer callbacks do not crash")
    func concurrentBufferCallbacks() async throws {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let mockDelegate = MockAudioCaptureDelegate()
        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )
        capture.delegate = mockDelegate

        try capture.startCapture()

        // Act - simulate concurrent buffer arrivals
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    mockEngine.simulateAudioBuffer(AudioBufferData(
                        samples: [[Float(i) * 0.01]],
                        frameLength: 1,
                        sampleRate: 48000,
                        channelCount: 1
                    ))
                }
            }
        }

        // Assert - all buffers should be captured
        #expect(mockDelegate.capturedBuffers.count == 100)
    }

    @Test("Start and stop from different tasks")
    func startStopFromDifferentTasks() async {
        // Arrange
        let mockEngine = MockAudioEngine()
        let mockPermission = MockPermissionChecker()
        mockPermission.setStatus(.authorized)

        let capture = MicrophoneCapture(
            audioEngine: mockEngine,
            permissionChecker: mockPermission
        )

        // Act - concurrent start/stop (implementation should handle gracefully)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? capture.startCapture()
            }
            group.addTask {
                try? capture.startCapture()
            }
            group.addTask {
                capture.stopCapture()
            }
        }

        // Assert - should not crash, final state is deterministic
        // (either capturing or not, but not in corrupted state)
        _ = capture.isCapturing  // Should not crash
    }
}
