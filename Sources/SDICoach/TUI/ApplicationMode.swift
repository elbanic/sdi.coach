// ApplicationMode.swift
// Task 5.3.5: Application mode state transitions
//
// Defines application modes and state machine for interview session management.

import Foundation

/// Application mode representing the current state of the interview session
public enum ApplicationMode: String, CaseIterable, Sendable, Equatable {
    case idle           // Waiting for /start
    case interviewing   // Active interview session
    case paused         // Interview paused
    case feedback       // Generating feedback report
}

/// Events that can trigger state transitions
public enum StateEvent: Sendable, Equatable {
    case start    // /start command
    case pause    // /pause command
    case resume   // /resume or /start when paused
    case end      // /end command
    case complete // Feedback generation complete
}

/// State machine for ApplicationMode transitions
///
/// State transition diagram:
/// ```
/// idle --start--> interviewing
/// interviewing --pause--> paused
/// interviewing --end--> feedback
/// paused --resume/start--> interviewing
/// paused --end--> feedback
/// feedback --complete--> idle
/// ```
public struct ApplicationStateMachine: @unchecked Sendable {
    private var _currentMode: ApplicationMode
    private var transitionCallbacks: [@Sendable (ApplicationMode, ApplicationMode) -> Void] = []
    private let lock = NSLock()

    public var currentMode: ApplicationMode {
        lock.lock()
        defer { lock.unlock() }
        return _currentMode
    }

    public init(initialMode: ApplicationMode = .idle) {
        self._currentMode = initialMode
    }

    /// Attempt to transition to a new state based on event
    /// - Returns: true if transition succeeded, false otherwise
    public mutating func transition(on event: StateEvent) -> Bool {
        lock.lock()
        guard let newMode = nextMode(for: event) else {
            lock.unlock()
            return false
        }

        let oldMode = _currentMode
        _currentMode = newMode
        let callbacks = transitionCallbacks
        lock.unlock()

        for callback in callbacks {
            callback(oldMode, newMode)
        }

        return true
    }

    /// Check if a transition is possible without performing it
    public func canTransition(on event: StateEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return nextMode(for: event) != nil
    }

    /// Get available transitions from current state
    public func availableTransitions() -> [StateEvent] {
        lock.lock()
        defer { lock.unlock() }

        var events: [StateEvent] = []
        for event in [StateEvent.start, .pause, .resume, .end, .complete] {
            if nextModeUnsafe(for: event) != nil {
                events.append(event)
            }
        }
        return events
    }

    /// Register callback for state transitions
    public mutating func onTransition(_ callback: @escaping @Sendable (ApplicationMode, ApplicationMode) -> Void) {
        lock.lock()
        transitionCallbacks.append(callback)
        lock.unlock()
    }

    /// Reset to idle state
    public mutating func reset() {
        lock.lock()
        _currentMode = .idle
        lock.unlock()
    }

    /// Determine next mode based on current mode and event (thread-safe)
    private func nextMode(for event: StateEvent) -> ApplicationMode? {
        return nextModeUnsafe(for: event)
    }

    /// Determine next mode based on current mode and event (not thread-safe, caller must hold lock)
    private func nextModeUnsafe(for event: StateEvent) -> ApplicationMode? {
        switch (_currentMode, event) {
        // From idle
        case (.idle, .start):
            return .interviewing

        // From interviewing
        case (.interviewing, .pause):
            return .paused
        case (.interviewing, .end):
            return .feedback

        // From paused
        case (.paused, .resume), (.paused, .start):
            return .interviewing
        case (.paused, .end):
            return .feedback

        // From feedback
        case (.feedback, .complete):
            return .idle

        // Invalid transitions
        default:
            return nil
        }
    }
}
