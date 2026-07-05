// IPC Protocol Types for sdi.coach
//
// Task 1.1.1: Define all IPC protocol message type enums for both Swift and Python.
//
// This file defines:
// - MessageType enum: All supported message types
// - MessageDirection enum: Message direction indicators
// - IPCMessage struct: The main message container
// - AnyCodable: Type-erased Codable wrapper for dynamic payloads
// - Factory functions: Convenience methods for creating common messages

import Foundation

// MARK: - Protocol Version

/// IPC Protocol version for handshake validation
/// Major version changes indicate breaking changes; minor versions are backward compatible
public let IPC_PROTOCOL_VERSION = "1.0"

/// Check if a server version is compatible with the client version
/// Compatibility rule: Same major version is compatible (e.g., 1.0 and 1.5 are compatible)
public func isVersionCompatible(_ serverVersion: String) -> Bool {
    let clientMajor = IPC_PROTOCOL_VERSION.split(separator: ".").first.map(String.init) ?? ""
    let serverMajor = serverVersion.split(separator: ".").first.map(String.init) ?? ""
    return clientMajor == serverMajor && !clientMajor.isEmpty
}

// MARK: - Base64 Helper Extension

extension Data {
    /// Initializes Data from a Base64 encoded string, automatically adding padding if needed.
    /// Standard Base64 decoding in Swift requires proper padding, but some systems (like Python)
    /// may omit padding characters. This helper adds the necessary padding before decoding.
    public init?(base64EncodedWithPadding string: String, options: Data.Base64DecodingOptions = []) {
        var base64 = string
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64, options: options)
    }
}

// MARK: - Flexible ISO8601 Date Parsing

extension DateFormatter {
    /// A flexible ISO8601 date formatter that handles timestamps with or without the "Z" suffix.
    /// Python's datetime.isoformat() produces timestamps like "2024-01-15T10:30:00" (no Z),
    /// while Swift's ISO8601DateFormatter expects "2024-01-15T10:30:00Z".
    public static let flexibleISO8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// A flexible ISO8601 date formatter that handles timestamps with fractional seconds.
    public static let flexibleISO8601WithFractionalSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

// MARK: - MessageType Enum

/// All supported IPC message types.
/// Raw values are snake_case strings for JSON serialization compatibility with Python backend.
public enum MessageType: String, Codable, CaseIterable {
    case audioData = "audio_data"
    case transcription = "transcription"
    case interviewStart = "interview_start"
    case interviewQuestion = "interview_question"
    case interviewResponse = "interview_response"
    case interviewFollowup = "interview_followup"
    case interviewEnd = "interview_end"
    case feedbackRequest = "feedback_request"
    case feedbackResponse = "feedback_response"
    case ttsSpeak = "tts_speak"
    case ttsStatus = "tts_status"
    case ttsStop = "tts_stop"
    // Protocol handshake (Task 1.1.3)
    case handshakeRequest = "handshake_request"
    case handshakeResponse = "handshake_response"
    // Error message for communicating backend errors to CLI
    case error = "error"
    // Timer end signal (Timer End Interview Guide feature)
    case interviewTimeUp = "interview_time_up"

    /// Returns the direction for this message type
    public var direction: MessageDirection {
        switch self {
        case .audioData, .interviewStart, .interviewResponse, .interviewEnd,
             .feedbackRequest, .ttsSpeak, .ttsStop, .handshakeRequest,
             .interviewTimeUp:
            return .cliToBackend
        case .transcription, .interviewQuestion, .interviewFollowup,
             .feedbackResponse, .ttsStatus, .handshakeResponse, .error:
            return .backendToCli
        }
    }

    /// Validates that a payload contains all required fields for this message type
    public func validatePayload(_ payload: [String: AnyCodable]) -> Bool {
        switch self {
        case .audioData:
            return payload["audio_base64"] != nil && payload["sample_rate"] != nil
        case .transcription:
            return payload["text"] != nil && payload["is_final"] != nil
        case .interviewStart:
            return payload["question"] != nil
        case .interviewQuestion:
            return payload["question"] != nil
        case .interviewResponse:
            return payload["response"] != nil
        case .interviewFollowup:
            return payload["question"] != nil
        case .interviewEnd:
            // Empty payload is valid for interview_end
            return true
        case .feedbackRequest:
            return payload["transcript"] != nil
        case .feedbackResponse:
            return payload["markdown"] != nil
        case .ttsSpeak:
            return payload["text"] != nil
        case .ttsStatus:
            return payload["status"] != nil
        case .ttsStop:
            // Empty payload is valid for tts_stop
            return true
        case .handshakeRequest:
            return payload["version"] != nil
        case .handshakeResponse:
            return payload["accepted"] != nil && payload["server_version"] != nil
        case .error:
            return payload["error"] != nil && payload["message"] != nil
        case .interviewTimeUp:
            // Empty payload is valid for interview_time_up
            return true
        }
    }
}

// MARK: - MessageDirection Enum

/// Direction of message flow
public enum MessageDirection: String, Codable {
    case cliToBackend = "cli_to_backend"
    case backendToCli = "backend_to_cli"
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for handling dynamic JSON payloads
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode value"))
        }
    }
}

// MARK: - IPCMessage Struct

/// The main IPC message container
public struct IPCMessage: Codable {
    public let type: MessageType
    public let payload: [String: AnyCodable]
    public let messageId: String?
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case type
        case payload
        case messageId = "message_id"
        case timestamp
    }

    public init(type: MessageType, payload: [String: AnyCodable], messageId: String? = nil, timestamp: Date = Date()) {
        self.type = type
        self.payload = payload
        self.messageId = messageId
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(MessageType.self, forKey: .type)
        payload = try container.decode([String: AnyCodable].self, forKey: .payload)
        messageId = try container.decodeIfPresent(String.self, forKey: .messageId)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(payload, forKey: .payload)
        try container.encodeIfPresent(messageId, forKey: .messageId)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

// MARK: - JSON Encoder/Decoder with ISO8601 Date Strategy

extension IPCMessage {
    /// Creates a JSONEncoder configured for IPC protocol compatibility (ISO8601 dates)
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Creates a JSONDecoder configured for IPC protocol compatibility (flexible ISO8601 dates)
    /// Supports both standard ISO8601 (with "Z" suffix) and Python's datetime.isoformat() format (without "Z")
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with Z suffix first (standard format)
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try ISO8601 with fractional seconds and Z suffix
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try Python's datetime.isoformat() format (no Z suffix)
            if let date = DateFormatter.flexibleISO8601.date(from: dateString) {
                return date
            }

            // Try Python's datetime.isoformat() with fractional seconds
            if let date = DateFormatter.flexibleISO8601WithFractionalSeconds.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to parse date string: \(dateString)"
            )
        }
        return decoder
    }

    /// Encodes this message to JSON data using ISO8601 date format
    public func toJSONData() throws -> Data {
        return try Self.makeEncoder().encode(self)
    }

    /// Encodes this message to JSON string using ISO8601 date format
    public func toJSONString() throws -> String {
        let data = try toJSONData()
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: [], debugDescription: "Failed to convert JSON data to string"))
        }
        return string
    }

    /// Decodes an IPCMessage from JSON data using ISO8601 date format
    public static func fromJSONData(_ data: Data) throws -> IPCMessage {
        return try makeDecoder().decode(IPCMessage.self, from: data)
    }

    /// Decodes an IPCMessage from JSON string using ISO8601 date format
    public static func fromJSONString(_ string: String) throws -> IPCMessage {
        guard let data = string.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Failed to convert string to data"))
        }
        return try fromJSONData(data)
    }
}

// MARK: - Factory Functions

extension IPCMessage {
    /// Creates an audio_data message
    public static func audioData(audioBase64: String, sampleRate: Int) -> IPCMessage {
        return IPCMessage(
            type: .audioData,
            payload: [
                "audio_base64": AnyCodable(audioBase64),
                "sample_rate": AnyCodable(sampleRate)
            ]
        )
    }

    /// Creates a transcription message
    public static func transcription(text: String, isFinal: Bool) -> IPCMessage {
        return IPCMessage(
            type: .transcription,
            payload: [
                "text": AnyCodable(text),
                "is_final": AnyCodable(isFinal)
            ]
        )
    }

    /// Creates an interview_start message
    public static func interviewStart(question: String) -> IPCMessage {
        return IPCMessage(
            type: .interviewStart,
            payload: [
                "question": AnyCodable(question)
            ]
        )
    }

    /// Creates an interview_question message
    public static func interviewQuestion(question: String) -> IPCMessage {
        return IPCMessage(
            type: .interviewQuestion,
            payload: [
                "question": AnyCodable(question)
            ]
        )
    }

    /// Creates an interview_response message
    public static func interviewResponse(response: String) -> IPCMessage {
        return IPCMessage(
            type: .interviewResponse,
            payload: [
                "response": AnyCodable(response)
            ]
        )
    }

    /// Creates an interview_followup message
    public static func interviewFollowup(question: String) -> IPCMessage {
        return IPCMessage(
            type: .interviewFollowup,
            payload: [
                "question": AnyCodable(question)
            ]
        )
    }

    /// Creates an interview_end message
    public static func interviewEnd(reason: String? = nil) -> IPCMessage {
        var payload: [String: AnyCodable] = [:]
        if let reason = reason {
            payload["reason"] = AnyCodable(reason)
        }
        return IPCMessage(type: .interviewEnd, payload: payload)
    }

    /// Creates a feedback_request message
    public static func feedbackRequest(transcript: [[String: String]]) -> IPCMessage {
        return IPCMessage(
            type: .feedbackRequest,
            payload: [
                "transcript": AnyCodable(transcript)
            ]
        )
    }

    /// Creates a feedback_response message
    public static func feedbackResponse(markdown: String) -> IPCMessage {
        return IPCMessage(
            type: .feedbackResponse,
            payload: [
                "markdown": AnyCodable(markdown)
            ]
        )
    }

    /// Creates a tts_speak message
    public static func ttsSpeak(text: String) -> IPCMessage {
        return IPCMessage(
            type: .ttsSpeak,
            payload: [
                "text": AnyCodable(text)
            ]
        )
    }

    /// Creates a tts_status message
    public static func ttsStatus(status: String, progress: Double? = nil) -> IPCMessage {
        var payload: [String: AnyCodable] = ["status": AnyCodable(status)]
        if let progress = progress {
            payload["progress"] = AnyCodable(progress)
        }
        return IPCMessage(type: .ttsStatus, payload: payload)
    }

    /// Creates a tts_stop message
    public static func ttsStop() -> IPCMessage {
        return IPCMessage(type: .ttsStop, payload: [:])
    }

    // MARK: - Handshake Messages (Task 1.1.3)

    /// Creates a handshake_request message with the client's protocol version
    public static func handshakeRequest() -> IPCMessage {
        return IPCMessage(
            type: .handshakeRequest,
            payload: [
                "version": AnyCodable(IPC_PROTOCOL_VERSION)
            ]
        )
    }

    /// Creates a handshake_response message from the server
    /// - Parameters:
    ///   - accepted: Whether the handshake was accepted
    ///   - serverVersion: The server's protocol version
    public static func handshakeResponse(accepted: Bool, serverVersion: String) -> IPCMessage {
        return IPCMessage(
            type: .handshakeResponse,
            payload: [
                "accepted": AnyCodable(accepted),
                "server_version": AnyCodable(serverVersion)
            ]
        )
    }

    // MARK: - Timer End Signal (Timer End Interview Guide feature)

    /// Creates an interview_time_up message to signal the backend that interview time has ended
    public static func interviewTimeUp() -> IPCMessage {
        return IPCMessage(type: .interviewTimeUp, payload: [:])
    }
}
