// HeaderView.swift
// Task 5.3.2: HeaderView - Logo display, version display, timer display
//
// This is a stub file for compilation. Full implementation pending.

import Foundation

/// Header view component for TUI
/// Displays logo, version, interview question, and remaining time
///
/// To be implemented as part of Task 5.3.2
public final class HeaderView: @unchecked Sendable {

    // MARK: - Properties

    /// Current terminal width
    public private(set) var terminalWidth: Int

    /// Maximum lines for display
    public let maxLines: Int

    /// Application version
    public let version: String

    /// Current interview question
    private var question: String?

    /// Remaining time string
    private var remainingTime: String = "30:00"

    private let lock = NSLock()

    // MARK: - Initialization

    public init() {
        self.terminalWidth = 80
        self.maxLines = 10
        self.version = "0.1.0"
    }

    public init(terminalWidth: Int) {
        self.terminalWidth = terminalWidth
        self.maxLines = 10
        self.version = "0.1.0"
    }

    public init(terminalWidth: Int, version: String) {
        self.terminalWidth = terminalWidth
        self.maxLines = 10
        self.version = version
    }

    public init(terminalWidth: Int, maxLines: Int) {
        self.terminalWidth = terminalWidth
        self.maxLines = maxLines
        self.version = "0.1.0"
    }

    // MARK: - State Management

    /// Set the interview question
    public func setQuestion(_ q: String) {
        lock.lock()
        question = q
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

    /// Render the header view
    /// - Parameters:
    ///   - useColors: Whether to use ANSI colors (default: true)
    ///   - clearPrevious: Whether to clear previous content (default: false)
    /// - Returns: Rendered header string
    public func render(useColors: Bool = true, clearPrevious: Bool = false) -> String {
        lock.lock()
        let q = question ?? "No question set"
        let time = remainingTime
        let width = terminalWidth
        let ver = version
        lock.unlock()

        var output = ""

        // Calculate effective width for content (minimum 20 for usability)
        let effectiveWidth = max(20, width)

        // Create separator line that fits the width
        let lineWidth = effectiveWidth
        let line = String(repeating: "=", count: lineWidth)

        if useColors {
            output += "\u{1B}[1;36m" // Bold cyan
        }

        output += line + "\n"

        // Title line - truncate if needed
        let titleText = "sdi.coach v\(ver)"
        let truncatedTitle = truncateToWidth(titleText, maxWidth: effectiveWidth - 2)
        output += "  " + truncatedTitle + "\n"

        // Question line - truncate if needed
        if !q.isEmpty && q != "No question set" {
            let questionPrefix = "Q: "
            let availableWidth = effectiveWidth - 2 - questionPrefix.count - 3 // 2 for indent, 3 for "..."
            if q.count > availableWidth {
                let truncatedQ = String(q.prefix(availableWidth)) + "..."
                output += "  " + questionPrefix + truncatedQ + "\n"
            } else {
                output += "  " + questionPrefix + q + "\n"
            }
        }

        // Time line - truncate if needed
        let timeText = "Time Remaining: \(time)"
        let truncatedTime = truncateToWidth(timeText, maxWidth: effectiveWidth - 2)
        output += "  " + truncatedTime + "\n"

        output += line + "\n"

        if useColors {
            output += "\u{1B}[0m" // Reset
        }

        return output
    }

    /// Truncate a string to fit within maxWidth
    private func truncateToWidth(_ text: String, maxWidth: Int) -> String {
        guard text.count > maxWidth else { return text }
        guard maxWidth > 3 else { return String(text.prefix(maxWidth)) }
        return String(text.prefix(maxWidth - 3)) + "..."
    }
}
