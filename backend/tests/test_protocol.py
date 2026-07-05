"""
Tests for IPC Protocol Message Types

Task 1.1.1: Define all IPC protocol message type enums for both Swift and Python.

These tests verify:
1. All required message types are defined
2. Message types can be serialized to JSON
3. Message types can be deserialized from JSON
4. Round-trip encoding/decoding preserves data integrity

Message Types from PRD.md:
| Message Type       | Direction       | Description                    |
|--------------------|-----------------|--------------------------------|
| audio_data         | CLI -> Backend  | Mic audio samples (Base64)     |
| transcription      | Backend -> CLI  | Transcribed text               |
| interview_start    | CLI -> Backend  | Start interview with question  |
| interview_question | Backend -> CLI  | AI-generated question          |
| interview_response | CLI -> Backend  | User's transcribed response    |
| interview_followup | Backend -> CLI  | Follow-up question from AI     |
| interview_end      | CLI -> Backend  | End interview session          |
| feedback_request   | CLI -> Backend  | Request feedback generation    |
| feedback_response  | Backend -> CLI  | Feedback markdown content      |
| tts_speak          | CLI -> Backend  | Request TTS playback           |
| tts_status         | Backend -> CLI  | TTS state update               |
| tts_stop           | CLI -> Backend  | Stop TTS playback              |
"""

import json
import pytest
from dataclasses import dataclass
from typing import Any


# Expected message type values (snake_case for JSON serialization)
EXPECTED_MESSAGE_TYPES = [
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
    # Protocol handshake (Task 1.1.3)
    "handshake_request",
    "handshake_response",
]

# Message types sent from CLI to Backend
CLI_TO_BACKEND_TYPES = [
    "audio_data",
    "interview_start",
    "interview_response",
    "interview_end",
    "feedback_request",
    "tts_speak",
    "tts_stop",
]

# Message types sent from Backend to CLI
BACKEND_TO_CLI_TYPES = [
    "transcription",
    "interview_question",
    "interview_followup",
    "feedback_response",
    "tts_status",
]


class TestMessageTypeEnum:
    """Test that all message types are defined in the MessageType enum."""

    def test_message_type_enum_exists(self):
        """MessageType enum should be importable from protocol module."""
        # This test will FAIL until protocol.py defines MessageType
        from ipc.protocol import MessageType

        assert MessageType is not None

    def test_all_message_types_defined(self):
        """All required message types should be defined in the enum."""
        from ipc.protocol import MessageType

        for msg_type in EXPECTED_MESSAGE_TYPES:
            # Check that each message type exists as an enum member
            # Enum members should be uppercase: audio_data -> AUDIO_DATA
            enum_name = msg_type.upper()
            assert hasattr(
                MessageType, enum_name
            ), f"MessageType.{enum_name} should be defined"

    def test_message_type_values_are_snake_case(self):
        """Message type values should be snake_case strings for JSON serialization."""
        from ipc.protocol import MessageType

        for msg_type in EXPECTED_MESSAGE_TYPES:
            enum_name = msg_type.upper()
            member = getattr(MessageType, enum_name)
            assert (
                member.value == msg_type
            ), f"MessageType.{enum_name}.value should be '{msg_type}'"

    def test_no_extra_message_types(self):
        """Only expected message types should be defined."""
        from ipc.protocol import MessageType

        actual_values = {member.value for member in MessageType}
        expected_values = set(EXPECTED_MESSAGE_TYPES)
        assert actual_values == expected_values, (
            f"MessageType should only contain expected types. "
            f"Extra: {actual_values - expected_values}, "
            f"Missing: {expected_values - actual_values}"
        )


class TestMessageDirection:
    """Test message direction classification."""

    def test_message_direction_enum_exists(self):
        """MessageDirection enum should be defined."""
        from ipc.protocol import MessageDirection

        assert MessageDirection is not None

    def test_message_direction_values(self):
        """MessageDirection should have CLI_TO_BACKEND and BACKEND_TO_CLI values."""
        from ipc.protocol import MessageDirection

        assert hasattr(MessageDirection, "CLI_TO_BACKEND")
        assert hasattr(MessageDirection, "BACKEND_TO_CLI")
        assert MessageDirection.CLI_TO_BACKEND.value == "cli_to_backend"
        assert MessageDirection.BACKEND_TO_CLI.value == "backend_to_cli"

    def test_get_direction_for_message_type(self):
        """Should be able to get direction for each message type."""
        from ipc.protocol import MessageType, get_message_direction, MessageDirection

        # Test CLI -> Backend types
        for msg_type in CLI_TO_BACKEND_TYPES:
            enum_member = getattr(MessageType, msg_type.upper())
            direction = get_message_direction(enum_member)
            assert direction == MessageDirection.CLI_TO_BACKEND, (
                f"{msg_type} should be CLI_TO_BACKEND"
            )

        # Test Backend -> CLI types
        for msg_type in BACKEND_TO_CLI_TYPES:
            enum_member = getattr(MessageType, msg_type.upper())
            direction = get_message_direction(enum_member)
            assert direction == MessageDirection.BACKEND_TO_CLI, (
                f"{msg_type} should be BACKEND_TO_CLI"
            )


class TestIPCMessage:
    """Test the IPCMessage dataclass."""

    def test_ipc_message_class_exists(self):
        """IPCMessage dataclass should be defined."""
        from ipc.protocol import IPCMessage

        assert IPCMessage is not None

    def test_ipc_message_has_required_fields(self):
        """IPCMessage should have type and payload fields."""
        from ipc.protocol import IPCMessage, MessageType

        msg = IPCMessage(type=MessageType.AUDIO_DATA, payload={"data": "test"})
        assert msg.type == MessageType.AUDIO_DATA
        assert msg.payload == {"data": "test"}

    def test_ipc_message_optional_id_field(self):
        """IPCMessage should have an optional message_id field."""
        from ipc.protocol import IPCMessage, MessageType

        # Without ID
        msg1 = IPCMessage(type=MessageType.AUDIO_DATA, payload={})
        assert msg1.message_id is None or hasattr(msg1, "message_id")

        # With ID
        msg2 = IPCMessage(
            type=MessageType.AUDIO_DATA, payload={}, message_id="test-123"
        )
        assert msg2.message_id == "test-123"


class TestJSONSerialization:
    """Test JSON serialization of IPC messages."""

    def test_message_type_to_json(self):
        """MessageType enum should serialize to its string value."""
        from ipc.protocol import MessageType

        for msg_type in EXPECTED_MESSAGE_TYPES:
            enum_member = getattr(MessageType, msg_type.upper())
            # Serialize to JSON should produce the snake_case string
            assert json.dumps(enum_member.value) == f'"{msg_type}"'

    def test_ipc_message_to_json(self):
        """IPCMessage should serialize to valid JSON."""
        from ipc.protocol import IPCMessage, MessageType, message_to_json

        msg = IPCMessage(
            type=MessageType.AUDIO_DATA,
            payload={"audio_base64": "SGVsbG8gV29ybGQ=", "sample_rate": 16000},
        )

        json_str = message_to_json(msg)
        parsed = json.loads(json_str)

        assert parsed["type"] == "audio_data"
        assert parsed["payload"]["audio_base64"] == "SGVsbG8gV29ybGQ="
        assert parsed["payload"]["sample_rate"] == 16000

    def test_ipc_message_from_json(self):
        """IPCMessage should deserialize from valid JSON."""
        from ipc.protocol import IPCMessage, MessageType, message_from_json

        json_str = json.dumps(
            {
                "type": "transcription",
                "payload": {"text": "Hello world", "is_final": True},
            }
        )

        msg = message_from_json(json_str)

        assert msg.type == MessageType.TRANSCRIPTION
        assert msg.payload["text"] == "Hello world"
        assert msg.payload["is_final"] is True

    def test_round_trip_serialization(self):
        """Serializing and deserializing should preserve message content."""
        from ipc.protocol import IPCMessage, MessageType, message_to_json, message_from_json

        original = IPCMessage(
            type=MessageType.INTERVIEW_START,
            payload={"question": "Design a URL shortener", "duration_minutes": 30},
            message_id="msg-001",
        )

        json_str = message_to_json(original)
        restored = message_from_json(json_str)

        assert restored.type == original.type
        assert restored.payload == original.payload
        assert restored.message_id == original.message_id


class TestMessageTypeRoundTrip:
    """Test round-trip encoding/decoding for each message type."""

    @pytest.mark.parametrize("msg_type", EXPECTED_MESSAGE_TYPES)
    def test_message_type_round_trip(self, msg_type: str):
        """Each message type should survive round-trip JSON encoding."""
        from ipc.protocol import IPCMessage, MessageType, message_to_json, message_from_json

        enum_member = getattr(MessageType, msg_type.upper())
        original = IPCMessage(type=enum_member, payload={"test_key": "test_value"})

        json_str = message_to_json(original)
        restored = message_from_json(json_str)

        assert restored.type == original.type
        assert restored.type.value == msg_type


class TestMessagePayloadValidation:
    """Test payload structure validation for different message types."""

    def test_audio_data_payload_structure(self):
        """audio_data messages should have audio_base64 and sample_rate."""
        from ipc.protocol import validate_payload, MessageType

        # Valid payload
        valid = {"audio_base64": "SGVsbG8=", "sample_rate": 16000}
        assert validate_payload(MessageType.AUDIO_DATA, valid) is True

        # Missing required field
        invalid = {"audio_base64": "SGVsbG8="}  # Missing sample_rate
        with pytest.raises(ValueError):
            validate_payload(MessageType.AUDIO_DATA, invalid)

    def test_transcription_payload_structure(self):
        """transcription messages should have text and is_final."""
        from ipc.protocol import validate_payload, MessageType

        valid = {"text": "Hello world", "is_final": True}
        assert validate_payload(MessageType.TRANSCRIPTION, valid) is True

        invalid = {"text": "Hello world"}  # Missing is_final
        with pytest.raises(ValueError):
            validate_payload(MessageType.TRANSCRIPTION, invalid)

    def test_interview_start_payload_structure(self):
        """interview_start messages should have question field."""
        from ipc.protocol import validate_payload, MessageType

        valid = {"question": "Design a distributed cache"}
        assert validate_payload(MessageType.INTERVIEW_START, valid) is True

        invalid = {}  # Missing question
        with pytest.raises(ValueError):
            validate_payload(MessageType.INTERVIEW_START, invalid)

    def test_interview_question_payload_structure(self):
        """interview_question messages should have question text."""
        from ipc.protocol import validate_payload, MessageType

        valid = {"question": "How would you handle cache invalidation?"}
        assert validate_payload(MessageType.INTERVIEW_QUESTION, valid) is True

    def test_interview_response_payload_structure(self):
        """interview_response messages should have response text."""
        from ipc.protocol import validate_payload, MessageType

        valid = {"response": "I would use a TTL-based approach"}
        assert validate_payload(MessageType.INTERVIEW_RESPONSE, valid) is True

    def test_interview_followup_payload_structure(self):
        """interview_followup messages should have followup question."""
        from ipc.protocol import validate_payload, MessageType

        valid = {"question": "What about write-through vs write-back?"}
        assert validate_payload(MessageType.INTERVIEW_FOLLOWUP, valid) is True

    def test_interview_end_payload_structure(self):
        """interview_end messages may have optional reason."""
        from ipc.protocol import validate_payload, MessageType

        # Empty payload is valid
        assert validate_payload(MessageType.INTERVIEW_END, {}) is True

        # With reason is also valid
        valid = {"reason": "timeout"}
        assert validate_payload(MessageType.INTERVIEW_END, valid) is True

    def test_feedback_request_payload_structure(self):
        """feedback_request messages should have transcript data."""
        from ipc.protocol import validate_payload, MessageType

        valid = {
            "transcript": [
                {"role": "interviewer", "content": "Question text"},
                {"role": "user", "content": "Answer text"},
            ]
        }
        assert validate_payload(MessageType.FEEDBACK_REQUEST, valid) is True

    def test_feedback_response_payload_structure(self):
        """feedback_response messages should have markdown content."""
        from ipc.protocol import validate_payload, MessageType

        valid = {"markdown": "# Feedback\n\n## Strengths\n- Good answer"}
        assert validate_payload(MessageType.FEEDBACK_RESPONSE, valid) is True

    def test_tts_speak_payload_structure(self):
        """tts_speak messages should have text to speak."""
        from ipc.protocol import validate_payload, MessageType

        valid = {"text": "Welcome to the interview"}
        assert validate_payload(MessageType.TTS_SPEAK, valid) is True

    def test_tts_status_payload_structure(self):
        """tts_status messages should have status state."""
        from ipc.protocol import validate_payload, MessageType

        valid = {"status": "speaking", "progress": 0.5}
        assert validate_payload(MessageType.TTS_STATUS, valid) is True

    def test_tts_stop_payload_structure(self):
        """tts_stop messages may have empty payload."""
        from ipc.protocol import validate_payload, MessageType

        assert validate_payload(MessageType.TTS_STOP, {}) is True


class TestInvalidMessageHandling:
    """Test handling of invalid messages."""

    def test_invalid_message_type_raises_error(self):
        """Deserializing with invalid message type should raise error."""
        from ipc.protocol import message_from_json

        invalid_json = json.dumps({"type": "invalid_type", "payload": {}})

        with pytest.raises(ValueError) as exc_info:
            message_from_json(invalid_json)

        assert "invalid" in str(exc_info.value).lower()

    def test_missing_type_raises_error(self):
        """Deserializing without type field should raise error."""
        from ipc.protocol import message_from_json

        invalid_json = json.dumps({"payload": {}})

        with pytest.raises((ValueError, KeyError)):
            message_from_json(invalid_json)

    def test_missing_payload_raises_error(self):
        """Deserializing without payload field should raise error."""
        from ipc.protocol import message_from_json

        invalid_json = json.dumps({"type": "audio_data"})

        with pytest.raises((ValueError, KeyError)):
            message_from_json(invalid_json)

    def test_malformed_json_raises_error(self):
        """Deserializing malformed JSON should raise error."""
        from ipc.protocol import message_from_json

        with pytest.raises(json.JSONDecodeError):
            message_from_json("not valid json {")


class TestFactoryFunctions:
    """Test convenience factory functions for creating messages."""

    def test_create_audio_data_message(self):
        """Factory function for audio_data messages."""
        from ipc.protocol import create_audio_data_message, MessageType

        msg = create_audio_data_message(
            audio_base64="SGVsbG8gV29ybGQ=", sample_rate=16000
        )

        assert msg.type == MessageType.AUDIO_DATA
        assert msg.payload["audio_base64"] == "SGVsbG8gV29ybGQ="
        assert msg.payload["sample_rate"] == 16000

    def test_create_transcription_message(self):
        """Factory function for transcription messages."""
        from ipc.protocol import create_transcription_message, MessageType

        msg = create_transcription_message(text="Hello world", is_final=True)

        assert msg.type == MessageType.TRANSCRIPTION
        assert msg.payload["text"] == "Hello world"
        assert msg.payload["is_final"] is True

    def test_create_interview_start_message(self):
        """Factory function for interview_start messages."""
        from ipc.protocol import create_interview_start_message, MessageType

        msg = create_interview_start_message(question="Design a URL shortener")

        assert msg.type == MessageType.INTERVIEW_START
        assert msg.payload["question"] == "Design a URL shortener"

    def test_create_tts_speak_message(self):
        """Factory function for tts_speak messages."""
        from ipc.protocol import create_tts_speak_message, MessageType

        msg = create_tts_speak_message(text="Welcome to the interview")

        assert msg.type == MessageType.TTS_SPEAK
        assert msg.payload["text"] == "Welcome to the interview"


# Task 1.1.3: Protocol Version Handshake Tests

class TestProtocolVersionHandshake:
    """Test protocol version handshake functionality."""

    def test_protocol_version_constant_exists(self):
        """IPC_PROTOCOL_VERSION constant should be defined."""
        from ipc.protocol import IPC_PROTOCOL_VERSION

        assert IPC_PROTOCOL_VERSION == "1.0"

    def test_handshake_request_message_type_exists(self):
        """HANDSHAKE_REQUEST message type should be defined."""
        from ipc.protocol import MessageType

        assert hasattr(MessageType, "HANDSHAKE_REQUEST")
        assert MessageType.HANDSHAKE_REQUEST.value == "handshake_request"

    def test_handshake_response_message_type_exists(self):
        """HANDSHAKE_RESPONSE message type should be defined."""
        from ipc.protocol import MessageType

        assert hasattr(MessageType, "HANDSHAKE_RESPONSE")
        assert MessageType.HANDSHAKE_RESPONSE.value == "handshake_response"

    def test_create_handshake_request(self):
        """Factory function for handshake_request messages."""
        from ipc.protocol import create_handshake_request, MessageType, IPC_PROTOCOL_VERSION

        msg = create_handshake_request()

        assert msg.type == MessageType.HANDSHAKE_REQUEST
        assert msg.payload["version"] == IPC_PROTOCOL_VERSION

    def test_create_handshake_response_accepted(self):
        """Factory function for handshake_response messages (accepted)."""
        from ipc.protocol import create_handshake_response, MessageType

        msg = create_handshake_response(accepted=True, server_version="1.0")

        assert msg.type == MessageType.HANDSHAKE_RESPONSE
        assert msg.payload["accepted"] is True
        assert msg.payload["server_version"] == "1.0"

    def test_create_handshake_response_rejected(self):
        """Factory function for handshake_response messages (rejected)."""
        from ipc.protocol import create_handshake_response, MessageType

        msg = create_handshake_response(accepted=False, server_version="2.0")

        assert msg.type == MessageType.HANDSHAKE_RESPONSE
        assert msg.payload["accepted"] is False
        assert msg.payload["server_version"] == "2.0"

    def test_is_version_compatible_same_version(self):
        """Same version should be compatible."""
        from ipc.protocol import is_version_compatible

        assert is_version_compatible("1.0") is True

    def test_is_version_compatible_same_major_version(self):
        """Same major version (1.x) should be compatible."""
        from ipc.protocol import is_version_compatible

        assert is_version_compatible("1.1") is True
        assert is_version_compatible("1.5") is True

    def test_is_version_incompatible_different_major_version(self):
        """Different major version should be incompatible."""
        from ipc.protocol import is_version_compatible

        assert is_version_compatible("2.0") is False
        assert is_version_compatible("0.9") is False

    def test_handshake_message_directions(self):
        """Handshake messages should have correct directions."""
        from ipc.protocol import MessageType, get_message_direction, MessageDirection

        # handshake_request: CLI -> Backend
        assert get_message_direction(MessageType.HANDSHAKE_REQUEST) == MessageDirection.CLI_TO_BACKEND
        # handshake_response: Backend -> CLI
        assert get_message_direction(MessageType.HANDSHAKE_RESPONSE) == MessageDirection.BACKEND_TO_CLI

    def test_handshake_round_trip(self):
        """Handshake messages should survive round-trip JSON encoding."""
        from ipc.protocol import (
            create_handshake_request,
            create_handshake_response,
            message_to_json,
            message_from_json,
            MessageType,
        )

        # Test request round-trip
        request = create_handshake_request()
        request_json = message_to_json(request)
        request_restored = message_from_json(request_json)
        assert request_restored.type == MessageType.HANDSHAKE_REQUEST
        assert request_restored.payload["version"] == "1.0"

        # Test response round-trip
        response = create_handshake_response(accepted=True, server_version="1.0")
        response_json = message_to_json(response)
        response_restored = message_from_json(response_json)
        assert response_restored.type == MessageType.HANDSHAKE_RESPONSE
        assert response_restored.payload["accepted"] is True

    def test_handshake_request_payload_validation(self):
        """handshake_request payload should require version field."""
        from ipc.protocol import validate_payload, MessageType

        # Valid payload
        valid = {"version": "1.0"}
        assert validate_payload(MessageType.HANDSHAKE_REQUEST, valid) is True

        # Invalid payload (missing version)
        invalid = {}
        with pytest.raises(ValueError):
            validate_payload(MessageType.HANDSHAKE_REQUEST, invalid)

    def test_handshake_response_payload_validation(self):
        """handshake_response payload should require accepted and server_version fields."""
        from ipc.protocol import validate_payload, MessageType

        # Valid payload
        valid = {"accepted": True, "server_version": "1.0"}
        assert validate_payload(MessageType.HANDSHAKE_RESPONSE, valid) is True

        # Invalid payload (missing server_version)
        invalid = {"accepted": True}
        with pytest.raises(ValueError):
            validate_payload(MessageType.HANDSHAKE_RESPONSE, invalid)
