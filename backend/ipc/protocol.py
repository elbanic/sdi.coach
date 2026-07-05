"""
IPC Protocol Types for sdi.coach

Task 1.1.1: Define all IPC protocol message type enums for both Swift and Python.

This file defines:
- MessageType enum: All supported message types
- MessageDirection enum: Message direction indicators
- IPCMessage dataclass: The main message container
- Factory functions: Convenience methods for creating common messages
- JSON serialization: to_json, from_json helpers
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any

# Type aliases for improved readability
Payload = dict[str, Any]
TranscriptEntry = dict[str, str]

# Protocol version constant (Task 1.1.3)
# Major version changes indicate breaking changes; minor versions are backward compatible
IPC_PROTOCOL_VERSION = "1.0"


def is_version_compatible(client_version: str) -> bool:
    """Check if a client version is compatible with the server version.

    Compatibility rule: Same major version is compatible (e.g., 1.0 and 1.5 are compatible).

    Args:
        client_version: The client's protocol version string (e.g., "1.0", "1.5")

    Returns:
        True if compatible, False otherwise
    """
    server_major = IPC_PROTOCOL_VERSION.split(".")[0] if "." in IPC_PROTOCOL_VERSION else ""
    client_major = client_version.split(".")[0] if "." in client_version else ""
    return server_major == client_major and server_major != ""


class MessageType(Enum):
    """All supported IPC message types.

    Values are snake_case strings for JSON serialization compatibility.
    """
    AUDIO_DATA = "audio_data"
    TRANSCRIPTION = "transcription"
    INTERVIEW_START = "interview_start"
    INTERVIEW_QUESTION = "interview_question"
    INTERVIEW_RESPONSE = "interview_response"
    INTERVIEW_FOLLOWUP = "interview_followup"
    INTERVIEW_END = "interview_end"
    FEEDBACK_REQUEST = "feedback_request"
    FEEDBACK_RESPONSE = "feedback_response"
    TTS_SPEAK = "tts_speak"
    TTS_STATUS = "tts_status"
    TTS_STOP = "tts_stop"
    # Protocol handshake (Task 1.1.3)
    HANDSHAKE_REQUEST = "handshake_request"
    HANDSHAKE_RESPONSE = "handshake_response"
    # Error message for communicating backend errors to CLI
    ERROR = "error"
    # Timer end signal (Timer End Interview Guide feature)
    INTERVIEW_TIME_UP = "interview_time_up"


class MessageDirection(Enum):
    """Direction of message flow."""
    CLI_TO_BACKEND = "cli_to_backend"
    BACKEND_TO_CLI = "backend_to_cli"


# Mapping of message types to their directions
_MESSAGE_DIRECTIONS = {
    MessageType.AUDIO_DATA: MessageDirection.CLI_TO_BACKEND,
    MessageType.INTERVIEW_START: MessageDirection.CLI_TO_BACKEND,
    MessageType.INTERVIEW_RESPONSE: MessageDirection.CLI_TO_BACKEND,
    MessageType.INTERVIEW_END: MessageDirection.CLI_TO_BACKEND,
    MessageType.FEEDBACK_REQUEST: MessageDirection.CLI_TO_BACKEND,
    MessageType.TTS_SPEAK: MessageDirection.CLI_TO_BACKEND,
    MessageType.TTS_STOP: MessageDirection.CLI_TO_BACKEND,
    MessageType.HANDSHAKE_REQUEST: MessageDirection.CLI_TO_BACKEND,
    MessageType.INTERVIEW_TIME_UP: MessageDirection.CLI_TO_BACKEND,
    MessageType.TRANSCRIPTION: MessageDirection.BACKEND_TO_CLI,
    MessageType.INTERVIEW_QUESTION: MessageDirection.BACKEND_TO_CLI,
    MessageType.INTERVIEW_FOLLOWUP: MessageDirection.BACKEND_TO_CLI,
    MessageType.FEEDBACK_RESPONSE: MessageDirection.BACKEND_TO_CLI,
    MessageType.TTS_STATUS: MessageDirection.BACKEND_TO_CLI,
    MessageType.HANDSHAKE_RESPONSE: MessageDirection.BACKEND_TO_CLI,
    MessageType.ERROR: MessageDirection.BACKEND_TO_CLI,
}


def get_message_direction(message_type: MessageType) -> MessageDirection:
    """Get the direction for a given message type."""
    return _MESSAGE_DIRECTIONS[message_type]


# Required fields for each message type
_REQUIRED_FIELDS = {
    MessageType.AUDIO_DATA: ["audio_base64", "sample_rate"],
    MessageType.TRANSCRIPTION: ["text", "is_final"],
    MessageType.INTERVIEW_START: ["question"],
    MessageType.INTERVIEW_QUESTION: ["question"],
    MessageType.INTERVIEW_RESPONSE: ["response"],
    MessageType.INTERVIEW_FOLLOWUP: ["question"],
    MessageType.INTERVIEW_END: [],  # Empty payload is valid
    MessageType.FEEDBACK_REQUEST: ["transcript"],
    MessageType.FEEDBACK_RESPONSE: ["markdown"],
    MessageType.TTS_SPEAK: ["text"],
    MessageType.TTS_STATUS: ["status"],
    MessageType.TTS_STOP: [],  # Empty payload is valid
    # Handshake messages (Task 1.1.3)
    MessageType.HANDSHAKE_REQUEST: ["version"],
    MessageType.HANDSHAKE_RESPONSE: ["accepted", "server_version"],
    # Error message
    MessageType.ERROR: ["error", "message"],
    # Timer end signal
    MessageType.INTERVIEW_TIME_UP: [],  # Empty payload is valid
}


def validate_payload(message_type: MessageType, payload: Payload) -> bool:
    """Validate that a payload contains all required fields for a message type.

    Args:
        message_type: The type of message to validate
        payload: The payload dictionary to validate

    Returns:
        True if valid

    Raises:
        ValueError: If required fields are missing
    """
    required = _REQUIRED_FIELDS.get(message_type, [])
    missing = [field for field in required if field not in payload]
    if missing:
        raise ValueError(f"Missing required fields for {message_type.value}: {missing}")
    return True


@dataclass
class IPCMessage:
    """The main IPC message container."""
    type: MessageType
    payload: Payload
    message_id: str | None = None
    timestamp: datetime = field(default_factory=datetime.now)


def message_to_json(message: IPCMessage) -> str:
    """Serialize an IPCMessage to JSON string.

    Args:
        message: The IPCMessage to serialize

    Returns:
        JSON string representation
    """
    data = {
        "type": message.type.value,
        "payload": message.payload,
    }
    if message.message_id is not None:
        data["message_id"] = message.message_id
    if message.timestamp is not None:
        data["timestamp"] = message.timestamp.isoformat()
    return json.dumps(data)


def message_from_json(json_str: str) -> IPCMessage:
    """Deserialize an IPCMessage from JSON string.

    Args:
        json_str: JSON string to deserialize

    Returns:
        IPCMessage instance

    Raises:
        ValueError: If the message type is invalid
        KeyError: If required fields are missing
        json.JSONDecodeError: If JSON is malformed
    """
    data = json.loads(json_str)

    type_str = data["type"]
    payload = data["payload"]
    message_id = data.get("message_id")
    timestamp_str = data.get("timestamp")

    # Find matching MessageType
    message_type = None
    for mt in MessageType:
        if mt.value == type_str:
            message_type = mt
            break

    if message_type is None:
        raise ValueError(f"Invalid message type: {type_str}")

    # Parse timestamp if present
    timestamp = datetime.now()
    if timestamp_str:
        try:
            timestamp = datetime.fromisoformat(timestamp_str)
        except ValueError:
            pass  # Use current time if parsing fails

    return IPCMessage(
        type=message_type,
        payload=payload,
        message_id=message_id,
        timestamp=timestamp,
    )


# Factory functions for creating messages

def create_audio_data_message(
    audio_base64: str,
    sample_rate: int,
    message_id: str | None = None,
) -> IPCMessage:
    """Create an audio_data message."""
    return IPCMessage(
        type=MessageType.AUDIO_DATA,
        payload={"audio_base64": audio_base64, "sample_rate": sample_rate},
        message_id=message_id,
    )


def create_transcription_message(
    text: str,
    is_final: bool,
    message_id: str | None = None,
) -> IPCMessage:
    """Create a transcription message."""
    return IPCMessage(
        type=MessageType.TRANSCRIPTION,
        payload={"text": text, "is_final": is_final},
        message_id=message_id,
    )


def create_interview_start_message(
    question: str,
    message_id: str | None = None,
) -> IPCMessage:
    """Create an interview_start message."""
    return IPCMessage(
        type=MessageType.INTERVIEW_START,
        payload={"question": question},
        message_id=message_id,
    )


def create_interview_question_message(
    question: str,
    message_id: str | None = None,
) -> IPCMessage:
    """Create an interview_question message."""
    return IPCMessage(
        type=MessageType.INTERVIEW_QUESTION,
        payload={"question": question},
        message_id=message_id,
    )


def create_interview_response_message(
    response: str,
    message_id: str | None = None,
) -> IPCMessage:
    """Create an interview_response message."""
    return IPCMessage(
        type=MessageType.INTERVIEW_RESPONSE,
        payload={"response": response},
        message_id=message_id,
    )


def create_interview_followup_message(
    question: str,
    message_id: str | None = None,
) -> IPCMessage:
    """Create an interview_followup message."""
    return IPCMessage(
        type=MessageType.INTERVIEW_FOLLOWUP,
        payload={"question": question},
        message_id=message_id,
    )


def create_interview_end_message(
    reason: str | None = None,
    message_id: str | None = None,
) -> IPCMessage:
    """Create an interview_end message."""
    payload = {}
    if reason is not None:
        payload["reason"] = reason
    return IPCMessage(
        type=MessageType.INTERVIEW_END,
        payload=payload,
        message_id=message_id,
    )


def create_feedback_request_message(
    transcript: list[TranscriptEntry],
    message_id: str | None = None,
) -> IPCMessage:
    """Create a feedback_request message."""
    return IPCMessage(
        type=MessageType.FEEDBACK_REQUEST,
        payload={"transcript": transcript},
        message_id=message_id,
    )


def create_feedback_response_message(
    markdown: str,
    message_id: str | None = None,
) -> IPCMessage:
    """Create a feedback_response message."""
    return IPCMessage(
        type=MessageType.FEEDBACK_RESPONSE,
        payload={"markdown": markdown},
        message_id=message_id,
    )


def create_tts_speak_message(
    text: str,
    message_id: str | None = None,
) -> IPCMessage:
    """Create a tts_speak message."""
    return IPCMessage(
        type=MessageType.TTS_SPEAK,
        payload={"text": text},
        message_id=message_id,
    )


def create_tts_status_message(
    status: str,
    progress: float | None = None,
    message_id: str | None = None,
) -> IPCMessage:
    """Create a tts_status message."""
    payload = {"status": status}
    if progress is not None:
        payload["progress"] = progress
    return IPCMessage(
        type=MessageType.TTS_STATUS,
        payload=payload,
        message_id=message_id,
    )


def create_tts_stop_message(
    message_id: str | None = None,
) -> IPCMessage:
    """Create a tts_stop message."""
    return IPCMessage(
        type=MessageType.TTS_STOP,
        payload={},
        message_id=message_id,
    )


# Handshake factory functions (Task 1.1.3)

def create_handshake_request(
    message_id: str | None = None,
) -> IPCMessage:
    """Create a handshake_request message with the client's protocol version."""
    return IPCMessage(
        type=MessageType.HANDSHAKE_REQUEST,
        payload={"version": IPC_PROTOCOL_VERSION},
        message_id=message_id,
    )


def create_handshake_response(
    accepted: bool,
    server_version: str,
    message_id: str | None = None,
) -> IPCMessage:
    """Create a handshake_response message from the server.

    Args:
        accepted: Whether the handshake was accepted
        server_version: The server's protocol version
        message_id: Optional message ID
    """
    return IPCMessage(
        type=MessageType.HANDSHAKE_RESPONSE,
        payload={"accepted": accepted, "server_version": server_version},
        message_id=message_id,
    )


def create_error_message(
    error: str,
    message: str,
    message_id: str | None = None,
) -> IPCMessage:
    """Create an error message to communicate backend errors to CLI.

    Args:
        error: Error type/code (e.g., "interview_start_failed", "bedrock_error")
        message: Human-readable error message with details
        message_id: Optional message ID (should match the request that caused the error)
    """
    return IPCMessage(
        type=MessageType.ERROR,
        payload={"error": error, "message": message},
        message_id=message_id,
    )


# Timer end signal factory (Timer End Interview Guide feature)

def create_interview_time_up_message(
    message_id: str | None = None,
) -> IPCMessage:
    """Create an interview_time_up message to signal that interview time has ended.

    This message is sent from CLI to backend when the 30-minute timer reaches zero.
    The backend should instruct the interviewer agent to wrap up naturally.
    """
    return IPCMessage(
        type=MessageType.INTERVIEW_TIME_UP,
        payload={},
        message_id=message_id,
    )
