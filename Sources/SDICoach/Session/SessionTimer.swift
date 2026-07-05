// SessionTimer.swift
// Task 6.1.2: SessionTimer - 30-minute countdown timer with callbacks
//
// A thread-safe timer implementation using Swift actors for testable countdown functionality.
// Supports pause/resume, callbacks for tick and completion events.

import Foundation

// MARK: - TimeProviding Protocol

/// Protocol for time providers to enable testability
/// Implementation will use real Date() for production
public protocol TimeProviding: Sendable {
    func now() async -> TimeInterval
    func elapsedSinceTick() async -> TimeInterval
}

// MARK: - SessionTimer Actor

/// A thread-safe countdown timer for interview sessions
/// Uses Swift actor for concurrency safety and supports dependency injection for testability
public actor SessionTimer {

    // MARK: - Private State

    /// The initial duration set at initialization
    private let initialDurationSeconds: Int

    /// Current remaining time in seconds
    private var _remainingSeconds: Int

    /// Whether the timer is currently running
    private var _isRunning: Bool = false

    /// Whether the timer is paused (only valid when running)
    private var _isPaused: Bool = false

    /// Whether onComplete has been called for current run
    private var _hasCompletedOnce: Bool = false

    /// Injected time provider for future real-time integration.
    /// Note: Currently unused - use tick() method for manual time advancement in tests.
    /// Will be used when implementing automatic timer loop with real system time.
    private let timeProvider: TimeProviding?

    /// Callback invoked on each tick with remaining seconds
    private var onTickCallback: (@Sendable (Int) -> Void)?

    /// Callback invoked when timer reaches zero
    private var onCompleteCallback: (@Sendable () -> Void)?

    // MARK: - Initialization

    /// Initialize a session timer with specified duration
    /// - Parameters:
    ///   - durationSeconds: Total duration in seconds (default: 1800 = 30 minutes)
    ///   - timeProvider: Optional time provider for testing (nil uses real time)
    public init(durationSeconds: Int = 1800, timeProvider: TimeProviding? = nil) {
        self.initialDurationSeconds = durationSeconds
        self._remainingSeconds = durationSeconds
        self.timeProvider = timeProvider
    }

    // MARK: - Public State Properties

    /// Current remaining time in seconds
    public var remainingSeconds: Int {
        _remainingSeconds
    }

    /// Whether the timer is currently running
    public var isRunning: Bool {
        _isRunning
    }

    /// Whether the timer is paused
    public var isPaused: Bool {
        _isPaused
    }

    /// Formatted time string in "MM:SS" format
    public var formattedTime: String {
        let minutes = _remainingSeconds / 60
        let seconds = _remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Elapsed time in seconds since start
    public var elapsedSeconds: Int {
        initialDurationSeconds - _remainingSeconds
    }

    /// Total duration set at initialization
    public var totalDurationSeconds: Int {
        initialDurationSeconds
    }

    /// Progress percentage (0.0 to 100.0)
    public var progressPercentage: Double {
        guard initialDurationSeconds > 0 else { return 0.0 }
        return Double(elapsedSeconds) / Double(initialDurationSeconds) * 100.0
    }

    // MARK: - Control Methods

    /// Start the timer
    /// If already running, this is a no-op (does not reset time)
    public func start() async {
        guard !_isRunning else { return }

        _isRunning = true
        _isPaused = false

        // Handle zero duration - complete immediately
        if _remainingSeconds == 0 && !_hasCompletedOnce {
            _hasCompletedOnce = true
            _isRunning = false
            onCompleteCallback?()
        }
    }

    /// Pause the timer (only effective when running)
    /// Paused state keeps isRunning=true but stops time decrement
    public func pause() async {
        guard _isRunning else { return }
        _isPaused = true
    }

    /// Resume the timer from paused state
    public func resume() async {
        guard _isRunning else { return }
        _isPaused = false
    }

    /// Stop the timer completely
    /// Sets isRunning=false and isPaused=false, but preserves remaining time
    public func stop() async {
        _isRunning = false
        _isPaused = false
    }

    /// Reset the timer to initial duration
    /// Stops the timer and resets the onComplete flag
    public func reset() async {
        _isRunning = false
        _isPaused = false
        _remainingSeconds = initialDurationSeconds
        _hasCompletedOnce = false
    }

    /// Manual tick for time advancement - decrements by 1 second.
    /// This is the primary method for controlling timer progression in tests.
    /// Only works when running and not paused.
    public func tick() async {
        // No-op if not running, paused, or already at zero
        guard _isRunning && !_isPaused && _remainingSeconds > 0 else { return }

        // Decrement time
        _remainingSeconds -= 1

        // Call onTick callback with new remaining seconds
        onTickCallback?(_remainingSeconds)

        // Check for completion
        if _remainingSeconds == 0 && !_hasCompletedOnce {
            _hasCompletedOnce = true
            _isRunning = false
            onCompleteCallback?()
        }
    }

    // MARK: - Callback Setters

    /// Set the callback to be invoked on each tick
    /// - Parameter callback: Closure receiving remaining seconds
    public func setOnTick(_ callback: @escaping @Sendable (Int) -> Void) async {
        onTickCallback = callback
    }

    /// Set the callback to be invoked when timer completes
    /// - Parameter callback: Closure called once when reaching zero
    public func setOnComplete(_ callback: @escaping @Sendable () -> Void) async {
        onCompleteCallback = callback
    }
}
