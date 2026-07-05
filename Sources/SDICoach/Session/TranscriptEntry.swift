// TranscriptEntry.swift
// Transcript types shared between InterviewSession and TUIEngine
//
// Extracted from TUIEngine.swift for better code organization

import Foundation

/// Transcript source - who spoke
public enum TranscriptSource: String, Sendable, Codable, Equatable {
    case interviewer
    case user
}

/// Transcript entry - a single transcript record
public struct TranscriptEntry: Sendable, Codable {
    public let source: TranscriptSource
    public let content: String
    public let timestamp: Date

    public init(source: TranscriptSource, content: String, timestamp: Date) {
        self.source = source
        self.content = content
        self.timestamp = timestamp
    }
}
