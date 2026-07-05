// StatusBar.swift
// Task 5.3.3: StatusBar - Interview status, microphone status, available commands
//
// This is a stub file for compilation. Full implementation pending.

import Foundation

/// Status bar component for TUI
/// Displays interview status, microphone status, timer, and available commands
///
/// To be implemented as part of Task 5.3.3
public final class StatusBar: @unchecked Sendable {

    // MARK: - Properties

    /// Current terminal width
    public private(set) var terminalWidth: Int

    /// Current application mode
    public private(set) var currentMode: ApplicationMode = .idle

    /// Whether microphone is on
    public private(set) var isMicrophoneOn: Bool = false

    /// Remaining time string
    public private(set) var remainingTime: String = "30:00"

    private let lock = NSLock()

    // MARK: - Initialization

    public init() {
        self.terminalWidth = 80
    }

    public init(terminalWidth: Int) {
        self.terminalWidth = terminalWidth
    }

    // MARK: - State Management

    /// Set application mode
    public func setMode(_ mode: ApplicationMode) {
        lock.lock()
        currentMode = mode
        lock.unlock()
    }

    /// Set microphone state
    public func setMicrophoneOn(_ on: Bool) {
        lock.lock()
        isMicrophoneOn = on
        lock.unlock()
    }

    /// Set remaining time
    public func setRemainingTime(_ time: String) {
        lock.lock()
        remainingTime = time
        lock.unlock()
    }

    /// Update terminal width
    public func setTerminalWidth(_ width: Int) {
        lock.lock()
        terminalWidth = width
        lock.unlock()
    }

    // MARK: - Rendering

    /// Render the status bar
    /// - Parameter useColors: Whether to use ANSI colors (default: true)
    /// - Returns: Rendered status bar string
    public func render(useColors: Bool = true) -> String {
        lock.lock()
        let mode = currentMode
        let micOn = isMicrophoneOn
        let time = remainingTime
        let width = terminalWidth
        lock.unlock()

        // Mode text
        let modeText: String
        let modeColor: String
        switch mode {
        case .idle:
            modeText = "Idle"
            modeColor = "37" // white
        case .interviewing:
            modeText = "Interview"
            modeColor = "32" // green
        case .paused:
            modeText = "Paused"
            modeColor = "33" // yellow
        case .feedback:
            modeText = "Feedback"
            modeColor = "36" // cyan
        }

        // Mic text
        let micText = micOn ? "MIC ON" : "MIC OFF"
        let micColor = micOn ? "32" : "31" // green or red

        // Command hints
        let commands: String
        switch mode {
        case .idle:
            commands = "/start"
        case .interviewing:
            commands = "/pause /end"
        case .paused:
            commands = "/start /end"
        case .feedback:
            commands = "/quit"
        }

        // Build output
        var output = ""
        let separator = " | "

        if useColors {
            output += "\u{1B}[1;\(modeColor)m\(modeText)\u{1B}[0m"
            output += separator
            output += "\u{1B}[\(micColor)m\(micText)\u{1B}[0m"
            output += separator
            output += "\u{1B}[36m\(time)\u{1B}[0m"
            output += separator
            output += "\u{1B}[33m\(commands)\u{1B}[0m"
        } else {
            output = "\(modeText)\(separator)\(micText)\(separator)\(time)\(separator)\(commands)"
        }

        // Truncate if needed
        let plainLength = "\(modeText)\(separator)\(micText)\(separator)\(time)\(separator)\(commands)".count
        if plainLength > width {
            // Narrow mode - show essentials
            if useColors {
                output = "\u{1B}[1;\(modeColor)m\(modeText)\u{1B}[0m | \u{1B}[36m\(time)\u{1B}[0m"
            } else {
                output = "\(modeText) | \(time)"
            }
        }

        return output
    }

    /// Render prompt line
    /// - Parameter currentInput: Current input text (default: empty)
    /// - Returns: Rendered prompt line
    public func renderPromptLine(currentInput: String = "") -> String {
        return "> \(currentInput)"
    }

    /// Render status bar with prompt
    /// - Returns: Full output with status bar and prompt on new line
    public func renderWithPrompt() -> String {
        return render() + "\n" + renderPromptLine()
    }
}
