// TranscriptView.swift
// Task 5.3.4: TranscriptView - Real-time conversation display
//
// This is a stub file for compilation. Full implementation pending.

import Foundation

/// Transcript view component for TUI
/// Displays real-time conversation with interviewer and user messages
///
/// To be implemented as part of Task 5.3.4
public final class TranscriptView: @unchecked Sendable {

    // MARK: - Properties

    /// Current terminal width
    public private(set) var terminalWidth: Int

    /// Maximum lines to retain
    public let maxLines: Int

    /// Number of transcripts
    public var transcriptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return messages.count
    }

    private var messages: [TranscriptEntry] = []
    private var lastRenderedIndex: Int = -1
    private let lock = NSLock()

    // MARK: - Initialization

    public init() {
        self.terminalWidth = 80
        self.maxLines = 1000
    }

    public init(terminalWidth: Int) {
        self.terminalWidth = terminalWidth
        self.maxLines = 1000
    }

    public init(terminalWidth: Int, maxLines: Int) {
        self.terminalWidth = terminalWidth
        self.maxLines = maxLines
    }

    // MARK: - State Management

    /// Update terminal width
    public func setTerminalWidth(_ width: Int) {
        lock.lock()
        terminalWidth = width
        lock.unlock()
    }

    /// Add a message to the transcript
    public func addMessage(source: TranscriptSource, content: String, timestamp: Date) {
        let entry = TranscriptEntry(source: source, content: content, timestamp: timestamp)

        lock.lock()
        messages.append(entry)

        // Trim if exceeds maxLines
        if messages.count > maxLines {
            messages.removeFirst()
        }
        lock.unlock()
    }

    /// Clear all messages
    public func clear() {
        lock.lock()
        messages.removeAll()
        lastRenderedIndex = -1
        lock.unlock()
    }

    /// Get all messages
    public func getAllMessages() -> [TranscriptEntry] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    // MARK: - Rendering

    /// Render all transcripts
    /// - Parameter useColors: Whether to use ANSI colors (default: true)
    /// - Returns: Rendered transcript string
    public func render(useColors: Bool = true) -> String {
        lock.lock()
        let msgs = messages
        let width = terminalWidth
        lock.unlock()

        var output = ""

        for msg in msgs {
            output += formatMessage(msg, width: width, useColors: useColors)
            output += "\n"
        }

        return output
    }

    /// Render last N lines
    public func renderLastN(lines: Int) -> String {
        lock.lock()
        let msgs = messages.suffix(lines)
        let width = terminalWidth
        lock.unlock()

        var output = ""

        for msg in msgs {
            output += formatMessage(msg, width: width, useColors: true)
            output += "\n"
        }

        return output
    }

    /// Render only the latest message (for append-only mode)
    public func renderLatest() -> String {
        lock.lock()
        guard let lastMsg = messages.last else {
            lock.unlock()
            return ""
        }
        let width = terminalWidth
        lock.unlock()

        return formatMessage(lastMsg, width: width, useColors: true) + "\n"
    }

    /// Render a specific message by index
    public func renderMessage(at index: Int) -> String? {
        lock.lock()
        guard index >= 0 && index < messages.count else {
            lock.unlock()
            return nil
        }
        let msg = messages[index]
        let width = terminalWidth
        lock.unlock()

        return formatMessage(msg, width: width, useColors: true)
    }

    // MARK: - Export

    /// Export as plain text
    public func exportAsPlainText() -> String {
        lock.lock()
        let msgs = messages
        let width = terminalWidth
        lock.unlock()

        var output = ""

        for msg in msgs {
            output += formatMessage(msg, width: width, useColors: false)
            output += "\n"
        }

        return output
    }

    /// Export as markdown
    public func exportAsMarkdown() -> String {
        lock.lock()
        let msgs = messages
        lock.unlock()

        var output = "# Interview Transcript\n\n"

        for msg in msgs {
            let prefix = msg.source == .interviewer ? "**Interviewer**" : "**User**"
            let timeStr = formatTimestamp(msg.timestamp)
            output += "\(prefix) [\(timeStr)]:\n\(msg.content)\n\n"
        }

        return output
    }

    // MARK: - Private Helpers

    private func formatMessage(_ msg: TranscriptEntry, width: Int, useColors: Bool) -> String {
        let sourceIcon: String
        let sourceColor: String

        switch msg.source {
        case .interviewer:
            sourceIcon = "Bot"
            sourceColor = "36" // cyan
        case .user:
            sourceIcon = "User"
            sourceColor = "32" // green
        }

        let timeStr = formatTimestamp(msg.timestamp)
        let prefix: String

        if useColors {
            prefix = "\u{1B}[\(sourceColor)m[\(timeStr)] \(sourceIcon):\u{1B}[0m"
        } else {
            prefix = "[\(timeStr)] \(sourceIcon):"
        }

        // Wrap content if needed
        let prefixLength = "[\(timeStr)] \(sourceIcon): ".count
        let contentWidth = max(width - prefixLength, 20)
        let wrappedContent = wrapText(msg.content, maxWidth: contentWidth)

        return "\(prefix) \(wrappedContent)"
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func wrapText(_ text: String, maxWidth: Int) -> String {
        // Simple word wrap
        if text.count <= maxWidth {
            return text
        }

        var result = ""
        var currentLine = ""

        for word in text.split(separator: " ") {
            let wordStr = String(word)
            if currentLine.isEmpty {
                currentLine = wordStr
            } else if currentLine.count + 1 + wordStr.count <= maxWidth {
                currentLine += " " + wordStr
            } else {
                result += currentLine + "\n"
                currentLine = wordStr
            }
        }

        if !currentLine.isEmpty {
            result += currentLine
        }

        return result
    }
}
