/// Tests for IPC Protocol Message Types
///
/// Task 1.1.1: Define all IPC protocol message type enums for both Swift and Python.
///
/// These tests verify:
/// 1. All required message types are defined
/// 2. Message types can be encoded to JSON
/// 3. Message types can be decoded from JSON
/// 4. Round-trip encoding/decoding preserves data integrity
///
/// Message Types from PRD.md:
/// | Message Type       | Direction       | Description                    |
/// |---------------------|-----------------|--------------------------------|
/// | audio_data         | CLI -> Backend  | Mic audio samples (Base64)     |
/// | transcription      | Backend -> CLI  | Transcribed text               |
/// | interview_start    | CLI -> Backend  | Start interview with question  |
/// | interview_question | Backend -> CLI  | AI-generated question          |
/// | interview_response | CLI -> Backend  | User's transcribed response    |
/// | interview_followup | Backend -> CLI  | Follow-up question from AI     |
/// | interview_end      | CLI -> Backend  | End interview session          |
/// | feedback_request   | CLI -> Backend  | Request feedback generation    |
/// | feedback_response  | Backend -> CLI  | Feedback markdown content      |
/// | tts_speak          | CLI -> Backend  | Request TTS playback           |
/// | tts_status         | Backend -> CLI  | TTS state update               |
/// | tts_stop           | CLI -> Backend  | Stop TTS playback              |

import Foundation
import Testing
@testable import SDICoach

// MARK: - Expected Message Types

/// All message types that should be defined
let expectedMessageTypes: Set<String> = [
    "audio_data",
    "transcription",
    "interview_start",
    "interview_question",
    "interview_response",
    "interview_followup",
    "interview_end",
    "feedback_request",
    "feedback_response",
    "tts_speak",
    "tts_status",
    "tts_stop",
    // Protocol handshake (Task 1.1.3)
    "handshake_request",
    "handshake_response"
]

/// Message types sent from CLI to Backend
let cliToBackendTypes: Set<String> = [
    "audio_data",
    "interview_start",
    "interview_response",
    "interview_end",
    "feedback_request",
    "tts_speak",
    "tts_stop"
]

/// Message types sent from Backend to CLI
let backendToCliTypes: Set<String> = [
    "transcription",
    "interview_question",
    "interview_followup",
    "feedback_response",
    "tts_status"
]

// MARK: - MessageType Enum Tests

@Suite("MessageType Enum")
struct MessageTypeEnumTests {

    @Test("MessageType enum should be defined")
    func messageTypeExists() {
        // This test will FAIL until IPCProtocol.swift defines MessageType
        // The type should exist and be an enum
        let type = MessageType.self
        #expect(type == MessageType.self)
    }

    @Test("All message types should be defined")
    func allMessageTypesDefined() {
        // Test that all expected message types exist as enum cases
        #expect(MessageType.audioData.rawValue == "audio_data")
        #expect(MessageType.transcription.rawValue == "transcription")
        #expect(MessageType.interviewStart.rawValue == "interview_start")
        #expect(MessageType.interviewQuestion.rawValue == "interview_question")
        #expect(MessageType.interviewResponse.rawValue == "interview_response")
        #expect(MessageType.interviewFollowup.rawValue == "interview_followup")
        #expect(MessageType.interviewEnd.rawValue == "interview_end")
        #expect(MessageType.feedbackRequest.rawValue == "feedback_request")
        #expect(MessageType.feedbackResponse.rawValue == "feedback_response")
        #expect(MessageType.ttsSpeak.rawValue == "tts_speak")
        #expect(MessageType.ttsStatus.rawValue == "tts_status")
        #expect(MessageType.ttsStop.rawValue == "tts_stop")
    }

    @Test("MessageType should have exactly 16 cases")
    func messageTypeCount() {
        let allCases = MessageType.allCases
        #expect(allCases.count == 16)  // 12 original + 2 handshake + 1 error + 1 interviewTimeUp
    }

    @Test("MessageType raw values should be snake_case for JSON")
    func rawValuesAreSnakeCase() {
        for messageType in MessageType.allCases {
            let rawValue = messageType.rawValue
            // Check that raw value is snake_case (lowercase with underscores)
            #expect(rawValue == rawValue.lowercased())
            #expect(!rawValue.contains(where: { $0.isUppercase }))
        }
    }
}

// MARK: - MessageDirection Enum Tests

@Suite("MessageDirection Enum")
struct MessageDirectionEnumTests {

    @Test("MessageDirection enum should be defined")
    func messageDirectionExists() {
        let type = MessageDirection.self
        #expect(type == MessageDirection.self)
    }

    @Test("MessageDirection should have cliToBackend and backendToCli cases")
    func messageDirectionCases() {
        #expect(MessageDirection.cliToBackend.rawValue == "cli_to_backend")
        #expect(MessageDirection.backendToCli.rawValue == "backend_to_cli")
    }

    @Test("CLI to Backend message types should return correct direction")
    func cliToBackendDirection() {
        #expect(MessageType.audioData.direction == .cliToBackend)
        #expect(MessageType.interviewStart.direction == .cliToBackend)
        #expect(MessageType.interviewResponse.direction == .cliToBackend)
        #expect(MessageType.interviewEnd.direction == .cliToBackend)
        #expect(MessageType.feedbackRequest.direction == .cliToBackend)
        #expect(MessageType.ttsSpeak.direction == .cliToBackend)
        #expect(MessageType.ttsStop.direction == .cliToBackend)
    }

    @Test("Backend to CLI message types should return correct direction")
    func backendToCliDirection() {
        #expect(MessageType.transcription.direction == .backendToCli)
        #expect(MessageType.interviewQuestion.direction == .backendToCli)
        #expect(MessageType.interviewFollowup.direction == .backendToCli)
        #expect(MessageType.feedbackResponse.direction == .backendToCli)
        #expect(MessageType.ttsStatus.direction == .backendToCli)
    }
}

// MARK: - IPCMessage Struct Tests

@Suite("IPCMessage Struct")
struct IPCMessageTests {

    @Test("IPCMessage struct should be defined")
    func ipcMessageExists() {
        // IPCMessage should exist and be Codable
        let type = IPCMessage.self
        #expect(type == IPCMessage.self)
    }

    @Test("IPCMessage should have type and payload fields")
    func ipcMessageFields() {
        let payload: [String: AnyCodable] = ["data": AnyCodable("test")]
        let message = IPCMessage(type: .audioData, payload: payload)

        #expect(message.type == .audioData)
        #expect(message.payload["data"]?.value as? String == "test")
    }

    @Test("IPCMessage should have optional messageId field")
    func ipcMessageOptionalId() {
        // Without ID
        let message1 = IPCMessage(type: .audioData, payload: [:])
        #expect(message1.messageId == nil)

        // With ID
        let message2 = IPCMessage(type: .audioData, payload: [:], messageId: "test-123")
        #expect(message2.messageId == "test-123")
    }
}

// MARK: - JSON Encoding Tests

@Suite("JSON Encoding")
struct JSONEncodingTests {

    @Test("MessageType should encode to snake_case string")
    func messageTypeEncoding() throws {
        let encoder = JSONEncoder()

        let data = try encoder.encode(MessageType.audioData)
        let jsonString = String(data: data, encoding: .utf8)

        #expect(jsonString == "\"audio_data\"")
    }

    @Test("IPCMessage should encode to valid JSON")
    func ipcMessageEncoding() throws {
        let payload: [String: AnyCodable] = [
            "audio_base64": AnyCodable("SGVsbG8gV29ybGQ="),
            "sample_rate": AnyCodable(16000)
        ]
        let message = IPCMessage(type: .audioData, payload: payload)

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["type"] as? String == "audio_data")

        let decodedPayload = json?["payload"] as? [String: Any]
        #expect(decodedPayload?["audio_base64"] as? String == "SGVsbG8gV29ybGQ=")
        #expect(decodedPayload?["sample_rate"] as? Int == 16000)
    }

    @Test("IPCMessage with messageId should encode correctly")
    func ipcMessageWithIdEncoding() throws {
        let message = IPCMessage(
            type: .interviewStart,
            payload: ["question": AnyCodable("Design a URL shortener")],
            messageId: "msg-001"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["type"] as? String == "interview_start")
        #expect(json?["message_id"] as? String == "msg-001")
    }
}

// MARK: - JSON Decoding Tests

@Suite("JSON Decoding")
struct JSONDecodingTests {

    @Test("MessageType should decode from snake_case string")
    func messageTypeDecoding() throws {
        let jsonData = "\"audio_data\"".data(using: .utf8)!
        let decoder = JSONDecoder()

        let messageType = try decoder.decode(MessageType.self, from: jsonData)

        #expect(messageType == .audioData)
    }

    @Test("IPCMessage should decode from valid JSON")
    func ipcMessageDecoding() throws {
        let json = """
        {
            "type": "transcription",
            "payload": {
                "text": "Hello world",
                "is_final": true
            }
        }
        """

        let decoder = JSONDecoder()
        let message = try decoder.decode(IPCMessage.self, from: json.data(using: .utf8)!)

        #expect(message.type == .transcription)
        #expect(message.payload["text"]?.value as? String == "Hello world")
        #expect(message.payload["is_final"]?.value as? Bool == true)
    }

    @Test("IPCMessage with messageId should decode correctly")
    func ipcMessageWithIdDecoding() throws {
        let json = """
        {
            "type": "interview_start",
            "payload": {
                "question": "Design a URL shortener"
            },
            "message_id": "msg-001"
        }
        """

        let decoder = JSONDecoder()
        let message = try decoder.decode(IPCMessage.self, from: json.data(using: .utf8)!)

        #expect(message.type == .interviewStart)
        #expect(message.messageId == "msg-001")
    }

    @Test("Invalid message type should throw error")
    func invalidMessageTypeDecoding() {
        let json = """
        {
            "type": "invalid_type",
            "payload": {}
        }
        """

        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(IPCMessage.self, from: json.data(using: .utf8)!)
        }
    }
}

// MARK: - Round-Trip Tests

@Suite("Round-Trip Encoding/Decoding")
struct RoundTripTests {

    @Test("Each message type should survive round-trip encoding", arguments: MessageType.allCases)
    func messageTypeRoundTrip(messageType: MessageType) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(messageType)
        let decoded = try decoder.decode(MessageType.self, from: encoded)

        #expect(decoded == messageType)
        #expect(decoded.rawValue == messageType.rawValue)
    }

    @Test("IPCMessage should survive round-trip encoding")
    func ipcMessageRoundTrip() throws {
        let original = IPCMessage(
            type: .interviewStart,
            payload: [
                "question": AnyCodable("Design a URL shortener"),
                "duration_minutes": AnyCodable(30)
            ],
            messageId: "msg-001"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(IPCMessage.self, from: encoded)

        #expect(decoded.type == original.type)
        #expect(decoded.messageId == original.messageId)
        #expect(decoded.payload["question"]?.value as? String == "Design a URL shortener")
        #expect(decoded.payload["duration_minutes"]?.value as? Int == 30)
    }

    @Test("Complex payload should survive round-trip", arguments: MessageType.allCases)
    func complexPayloadRoundTrip(messageType: MessageType) throws {
        let complexPayload: [String: AnyCodable] = [
            "string_value": AnyCodable("test string"),
            "int_value": AnyCodable(42),
            "bool_value": AnyCodable(true),
            "double_value": AnyCodable(3.14),
            "array_value": AnyCodable(["a", "b", "c"]),
            "nested_object": AnyCodable(["key": "value"])
        ]

        let original = IPCMessage(type: messageType, payload: complexPayload)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(IPCMessage.self, from: encoded)

        #expect(decoded.type == original.type)
        #expect(decoded.payload["string_value"]?.value as? String == "test string")
        #expect(decoded.payload["int_value"]?.value as? Int == 42)
        #expect(decoded.payload["bool_value"]?.value as? Bool == true)
    }
}

// MARK: - Invalid Message Handling Tests

@Suite("Invalid Message Handling")
struct InvalidMessageHandlingTests {

    @Test("Missing type field should throw error")
    func missingTypeField() {
        let json = """
        {
            "payload": {}
        }
        """

        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(IPCMessage.self, from: json.data(using: .utf8)!)
        }
    }

    @Test("Missing payload field should throw error")
    func missingPayloadField() {
        let json = """
        {
            "type": "audio_data"
        }
        """

        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(IPCMessage.self, from: json.data(using: .utf8)!)
        }
    }

    @Test("Malformed JSON should throw error")
    func malformedJSON() {
        let malformedJSON = "not valid json {"

        let decoder = JSONDecoder()
        #expect(throws: Error.self) {
            _ = try decoder.decode(IPCMessage.self, from: malformedJSON.data(using: .utf8)!)
        }
    }
}

// MARK: - Factory Function Tests

@Suite("Factory Functions")
struct FactoryFunctionTests {

    @Test("createAudioDataMessage should create correct message")
    func createAudioDataMessage() {
        let message = IPCMessage.audioData(
            audioBase64: "SGVsbG8gV29ybGQ=",
            sampleRate: 16000
        )

        #expect(message.type == .audioData)
        #expect(message.payload["audio_base64"]?.value as? String == "SGVsbG8gV29ybGQ=")
        #expect(message.payload["sample_rate"]?.value as? Int == 16000)
    }

    @Test("createTranscriptionMessage should create correct message")
    func createTranscriptionMessage() {
        let message = IPCMessage.transcription(
            text: "Hello world",
            isFinal: true
        )

        #expect(message.type == .transcription)
        #expect(message.payload["text"]?.value as? String == "Hello world")
        #expect(message.payload["is_final"]?.value as? Bool == true)
    }

    @Test("createInterviewStartMessage should create correct message")
    func createInterviewStartMessage() {
        let message = IPCMessage.interviewStart(
            question: "Design a URL shortener"
        )

        #expect(message.type == .interviewStart)
        #expect(message.payload["question"]?.value as? String == "Design a URL shortener")
    }

    @Test("createTtsSpeakMessage should create correct message")
    func createTtsSpeakMessage() {
        let message = IPCMessage.ttsSpeak(
            text: "Welcome to the interview"
        )

        #expect(message.type == .ttsSpeak)
        #expect(message.payload["text"]?.value as? String == "Welcome to the interview")
    }
}

// MARK: - Payload Validation Tests

@Suite("Payload Validation")
struct PayloadValidationTests {

    @Test("audioData payload should require audio_base64 and sample_rate")
    func audioDataPayloadValidation() {
        // Valid payload
        let validPayload: [String: AnyCodable] = [
            "audio_base64": AnyCodable("SGVsbG8="),
            "sample_rate": AnyCodable(16000)
        ]
        #expect(MessageType.audioData.validatePayload(validPayload) == true)

        // Missing sample_rate
        let invalidPayload: [String: AnyCodable] = [
            "audio_base64": AnyCodable("SGVsbG8=")
        ]
        #expect(MessageType.audioData.validatePayload(invalidPayload) == false)
    }

    @Test("transcription payload should require text and is_final")
    func transcriptionPayloadValidation() {
        let validPayload: [String: AnyCodable] = [
            "text": AnyCodable("Hello"),
            "is_final": AnyCodable(true)
        ]
        #expect(MessageType.transcription.validatePayload(validPayload) == true)

        let invalidPayload: [String: AnyCodable] = [
            "text": AnyCodable("Hello")
        ]
        #expect(MessageType.transcription.validatePayload(invalidPayload) == false)
    }

    @Test("interviewStart payload should require question")
    func interviewStartPayloadValidation() {
        let validPayload: [String: AnyCodable] = [
            "question": AnyCodable("Design a cache")
        ]
        #expect(MessageType.interviewStart.validatePayload(validPayload) == true)

        let invalidPayload: [String: AnyCodable] = [:]
        #expect(MessageType.interviewStart.validatePayload(invalidPayload) == false)
    }

    @Test("ttsSpeak payload should require text")
    func ttsSpeakPayloadValidation() {
        let validPayload: [String: AnyCodable] = [
            "text": AnyCodable("Hello")
        ]
        #expect(MessageType.ttsSpeak.validatePayload(validPayload) == true)

        let invalidPayload: [String: AnyCodable] = [:]
        #expect(MessageType.ttsSpeak.validatePayload(invalidPayload) == false)
    }

    @Test("interviewEnd payload can be empty")
    func interviewEndPayloadValidation() {
        let emptyPayload: [String: AnyCodable] = [:]
        #expect(MessageType.interviewEnd.validatePayload(emptyPayload) == true)

        let payloadWithReason: [String: AnyCodable] = [
            "reason": AnyCodable("timeout")
        ]
        #expect(MessageType.interviewEnd.validatePayload(payloadWithReason) == true)
    }

    @Test("ttsStop payload can be empty")
    func ttsStopPayloadValidation() {
        let emptyPayload: [String: AnyCodable] = [:]
        #expect(MessageType.ttsStop.validatePayload(emptyPayload) == true)
    }
}

// MARK: - Protocol Version Handshake Tests (Task 1.1.3)

@Suite("Protocol Version Handshake")
struct ProtocolVersionHandshakeTests {

    @Test("IPC_PROTOCOL_VERSION constant should be defined")
    func protocolVersionConstantExists() {
        // Protocol version should be a string constant
        #expect(IPC_PROTOCOL_VERSION == "1.0")
    }

    @Test("handshakeRequest message type should be defined")
    func handshakeRequestMessageTypeExists() {
        #expect(MessageType.handshakeRequest.rawValue == "handshake_request")
    }

    @Test("handshakeResponse message type should be defined")
    func handshakeResponseMessageTypeExists() {
        #expect(MessageType.handshakeResponse.rawValue == "handshake_response")
    }

    @Test("handshakeRequest factory should create correct message")
    func handshakeRequestFactory() {
        let message = IPCMessage.handshakeRequest()

        #expect(message.type == .handshakeRequest)
        #expect(message.payload["version"]?.value as? String == IPC_PROTOCOL_VERSION)
    }

    @Test("handshakeResponse factory should create correct message for accepted")
    func handshakeResponseFactoryAccepted() {
        let message = IPCMessage.handshakeResponse(accepted: true, serverVersion: "1.0")

        #expect(message.type == .handshakeResponse)
        #expect(message.payload["accepted"]?.value as? Bool == true)
        #expect(message.payload["server_version"]?.value as? String == "1.0")
    }

    @Test("handshakeResponse factory should create correct message for rejected")
    func handshakeResponseFactoryRejected() {
        let message = IPCMessage.handshakeResponse(accepted: false, serverVersion: "2.0")

        #expect(message.type == .handshakeResponse)
        #expect(message.payload["accepted"]?.value as? Bool == false)
        #expect(message.payload["server_version"]?.value as? String == "2.0")
    }

    @Test("isVersionCompatible should return true for same version")
    func versionCompatibleSameVersion() {
        #expect(isVersionCompatible("1.0") == true)
    }

    @Test("isVersionCompatible should return true for same major version")
    func versionCompatibleSameMajorVersion() {
        // Same major version (1.x) should be compatible
        #expect(isVersionCompatible("1.1") == true)
        #expect(isVersionCompatible("1.5") == true)
    }

    @Test("isVersionCompatible should return false for different major version")
    func versionIncompatibleDifferentMajorVersion() {
        // Different major version should be incompatible
        #expect(isVersionCompatible("2.0") == false)
        #expect(isVersionCompatible("0.9") == false)
    }

    @Test("handshake messages should have correct direction")
    func handshakeMessageDirection() {
        // handshake_request: CLI -> Backend
        #expect(MessageType.handshakeRequest.direction == .cliToBackend)
        // handshake_response: Backend -> CLI
        #expect(MessageType.handshakeResponse.direction == .backendToCli)
    }

    @Test("handshake messages should survive round-trip encoding")
    func handshakeRoundTrip() throws {
        let request = IPCMessage.handshakeRequest()
        let response = IPCMessage.handshakeResponse(accepted: true, serverVersion: "1.0")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Test request round-trip
        let requestEncoded = try encoder.encode(request)
        let requestDecoded = try decoder.decode(IPCMessage.self, from: requestEncoded)
        #expect(requestDecoded.type == .handshakeRequest)
        #expect(requestDecoded.payload["version"]?.value as? String == "1.0")

        // Test response round-trip
        let responseEncoded = try encoder.encode(response)
        let responseDecoded = try decoder.decode(IPCMessage.self, from: responseEncoded)
        #expect(responseDecoded.type == .handshakeResponse)
        #expect(responseDecoded.payload["accepted"]?.value as? Bool == true)
    }

    @Test("handshakeRequest payload validation should require version")
    func handshakeRequestPayloadValidation() {
        let validPayload: [String: AnyCodable] = ["version": AnyCodable("1.0")]
        #expect(MessageType.handshakeRequest.validatePayload(validPayload) == true)

        let invalidPayload: [String: AnyCodable] = [:]
        #expect(MessageType.handshakeRequest.validatePayload(invalidPayload) == false)
    }

    @Test("handshakeResponse payload validation should require accepted and server_version")
    func handshakeResponsePayloadValidation() {
        let validPayload: [String: AnyCodable] = [
            "accepted": AnyCodable(true),
            "server_version": AnyCodable("1.0")
        ]
        #expect(MessageType.handshakeResponse.validatePayload(validPayload) == true)

        let invalidPayload: [String: AnyCodable] = ["accepted": AnyCodable(true)]
        #expect(MessageType.handshakeResponse.validatePayload(invalidPayload) == false)
    }
}
