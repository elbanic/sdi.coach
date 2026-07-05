// TranscriptManager.swift
// Task 6.1.3: TranscriptManager (accumulation, export)
//
// Thread-safe transcript manager for interview sessions.
// Handles transcript accumulation, statistics, and export.

import Foundation

/// Thread-safe transcript manager for accumulating and exporting interview transcripts.
/// Uses NSLock for thread safety with @unchecked Sendable.
public final class TranscriptManager: @unchecked Sendable, Codable {

    // MARK: - Constants

    /// Robot emoji for interviewer entries in Markdown export
    private static let interviewerEmoji = "\u{1F916}"

    /// Microphone emoji for user entries in Markdown export
    private static let userEmoji = "\u{1F3A4}"

    // MARK: - Private Properties

    /// Internal storage for transcript entries
    private var _entries: [TranscriptEntry]

    /// Lock for thread-safe access
    private let lock = NSLock()

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case entries
    }

    public func encode(to encoder: Encoder) throws {
        lock.lock()
        defer { lock.unlock() }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_entries, forKey: .entries)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _entries = try container.decode([TranscriptEntry].self, forKey: .entries)
    }

    // MARK: - Initialization

    /// Initialize with empty state
    public init() {
        _entries = []
    }

    /// Initialize with existing transcript entries
    /// - Parameter entries: Array of transcript entries to initialize with
    public init(entries: [TranscriptEntry]) {
        // Make defensive copy
        _entries = entries
    }

    // MARK: - Transcript Management

    /// Add a transcript entry
    /// - Parameter entry: The transcript entry to add
    public func add(entry: TranscriptEntry) {
        lock.lock()
        defer { lock.unlock() }
        _entries.append(entry)
    }

    /// Add a transcript with source and content (convenience method)
    /// - Parameters:
    ///   - source: The source of the transcript (interviewer or user)
    ///   - content: The content of the transcript
    public func add(source: TranscriptSource, content: String) {
        let entry = TranscriptEntry(source: source, content: content, timestamp: Date())
        add(entry: entry)
    }

    /// Clear all transcript entries
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        _entries.removeAll()
    }

    /// Get all entries (returns defensive copy)
    public var entries: [TranscriptEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    // MARK: - Statistics

    /// Total number of transcript entries
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _entries.count
    }

    /// Number of interviewer entries
    public var interviewerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _entries.filter { $0.source == .interviewer }.count
    }

    /// Number of user entries
    public var userCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _entries.filter { $0.source == .user }.count
    }

    /// Total word count across all entries
    /// Words are counted by splitting on whitespace
    public var totalWordCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _entries.reduce(0) { total, entry in
            let words = entry.content.split(whereSeparator: \.isWhitespace)
            return total + words.count
        }
    }

    // MARK: - Export Functions

    /// Export transcript as JSON string
    /// - Returns: JSON array string with source, content, and timestamp
    public func toJSON() -> String {
        lock.lock()
        let entriesCopy = _entries
        lock.unlock()

        if entriesCopy.isEmpty {
            return "[]"
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let jsonArray = entriesCopy.map { entry -> [String: String] in
            return [
                "source": entry.source.rawValue,
                "content": entry.content,
                "timestamp": dateFormatter.string(from: entry.timestamp)
            ]
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: jsonArray, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }

    /// Export transcript as Markdown string
    /// - Returns: Formatted Markdown with header and entries
    public func toMarkdown() -> String {
        lock.lock()
        let entriesCopy = _entries
        lock.unlock()

        var markdown = "# Interview Transcript\n"

        if entriesCopy.isEmpty {
            return markdown
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        for entry in entriesCopy {
            let timeString = timeFormatter.string(from: entry.timestamp)
            let sourceLabel: String
            let emoji: String

            switch entry.source {
            case .interviewer:
                sourceLabel = "Interviewer"
                emoji = Self.interviewerEmoji
            case .user:
                sourceLabel = "User"
                emoji = Self.userEmoji
            }

            markdown += "\n**\(emoji) \(sourceLabel)** (\(timeString)):\n"

            // Handle multi-line content with blockquote
            let lines = entry.content.components(separatedBy: "\n")
            for line in lines {
                markdown += "> \(line)\n"
            }
        }

        return markdown
    }

    /// Save transcript to a Markdown file
    /// - Parameter path: File path to save the transcript
    /// - Throws: Error if file writing fails
    public func saveToFile(_ path: String) throws {
        let markdown = toMarkdown()
        let url = URL(fileURLWithPath: path)

        // Create parent directory if needed
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Export transcript for feedback request
    /// - Parameter feedbackRequest: If true, uses "assistant"/"candidate" roles; otherwise "interviewer"/"user"
    /// - Returns: Array of dictionaries with "role" and "content" keys
    public func toFormattedTranscript(for feedbackRequest: Bool = false) -> [[String: String]] {
        lock.lock()
        let entriesCopy = _entries
        lock.unlock()

        return entriesCopy.map { entry in
            let role: String
            if feedbackRequest {
                role = entry.source == .interviewer ? "assistant" : "candidate"
            } else {
                role = entry.source == .interviewer ? "interviewer" : "user"
            }

            return [
                "role": role,
                "content": entry.content
            ]
        }
    }
}
