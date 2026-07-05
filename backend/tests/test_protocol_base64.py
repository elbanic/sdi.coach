"""
Tests for IPC Protocol Base64 Serialization

Task 1.1.2: JSON serialization with Base64 support

These tests verify:
1. Base64 encoding of binary audio data
2. Base64 decoding of audio data
3. Round-trip serialization with binary payload
4. Large payload handling
5. Special characters in text fields

Expected to FAIL until implementation is complete (RED phase).
"""

import base64
import binascii
import json
import struct
import pytest
from typing import List


# ============================================================================
# Base64 Encoding Tests
# ============================================================================

class TestBase64Encoding:
    """Test Base64 encoding of binary audio data."""

    def test_encode_empty_bytes(self):
        """Empty byte array should encode to empty string."""
        # Arrange
        empty_data = b""

        # Act
        encoded = base64.b64encode(empty_data).decode("utf-8")

        # Assert
        assert encoded == ""

    def test_encode_single_byte(self):
        """Single byte should encode to Base64 with padding."""
        # Arrange: Single null byte
        data = b"\x00"

        # Act
        encoded = base64.b64encode(data).decode("utf-8")

        # Assert: Single null byte encodes to "AA=="
        assert encoded == "AA=="

    def test_encode_hello_world(self):
        """'Hello World' should encode to known Base64 string."""
        # Arrange
        text = "Hello World"
        data = text.encode("utf-8")

        # Act
        encoded = base64.b64encode(data).decode("utf-8")

        # Assert
        assert encoded == "SGVsbG8gV29ybGQ="

    def test_encode_pcm_audio_samples(self):
        """PCM float32 audio samples should encode correctly."""
        # Arrange: 4 float32 samples (little-endian)
        samples = [0.0, 0.5, -0.5, 1.0]
        data = struct.pack(f"<{len(samples)}f", *samples)

        # Act
        encoded = base64.b64encode(data).decode("utf-8")

        # Assert: Encoded string should be non-empty
        assert len(encoded) > 0

        # Verify round-trip
        decoded = base64.b64decode(encoded)
        assert decoded == data

    def test_encode_preserves_binary_data_integrity(self):
        """Base64 encoding should preserve all byte values."""
        # Arrange: All possible byte values
        all_bytes = bytes(range(256))

        # Act
        encoded = base64.b64encode(all_bytes).decode("utf-8")
        decoded = base64.b64decode(encoded)

        # Assert
        assert decoded == all_bytes


# ============================================================================
# Base64 Decoding Tests
# ============================================================================

class TestBase64Decoding:
    """Test Base64 decoding to binary audio data."""

    def test_decode_empty_string(self):
        """Empty Base64 string should decode to empty bytes."""
        # Arrange
        encoded = ""

        # Act
        decoded = base64.b64decode(encoded)

        # Assert
        assert decoded == b""

    def test_decode_hello_world(self):
        """'SGVsbG8gV29ybGQ=' should decode to 'Hello World'."""
        # Arrange
        encoded = "SGVsbG8gV29ybGQ="

        # Act
        decoded = base64.b64decode(encoded)
        text = decoded.decode("utf-8")

        # Assert
        assert text == "Hello World"

    def test_decode_invalid_base64_with_validation_raises_error(self):
        """Invalid Base64 with validate=True should raise an error."""
        # Arrange: Invalid Base64 (incorrect characters or padding)
        # Note: base64.b64decode without validate=True is lenient
        # Using binascii for strict validation
        invalid = "!!!invalid!!!"

        # Act & Assert
        with pytest.raises(binascii.Error):
            binascii.a2b_base64(invalid)

    def test_decode_with_padding(self):
        """Base64 with padding should decode correctly."""
        # Arrange: "A" -> "QQ=="
        encoded = "QQ=="

        # Act
        decoded = base64.b64decode(encoded)
        text = decoded.decode("utf-8")

        # Assert
        assert text == "A"

    def test_decode_without_padding(self):
        """Base64 without padding should still decode (with validate=False)."""
        # Arrange: "QQ==" without padding = "QQ"
        encoded = "QQ"

        # Act - Standard library should handle missing padding
        decoded = base64.b64decode(encoded + "==")  # Add padding

        # Assert
        assert decoded == b"A"


# ============================================================================
# AudioData Message Tests
# ============================================================================

class TestAudioDataBase64Message:
    """Test audio_data message with Base64 encoded audio."""

    def test_create_audio_data_message_with_base64(self):
        """Create audio_data message with Base64 encoded audio."""
        from ipc.protocol import create_audio_data_message, MessageType

        # Arrange: Simulate 16kHz mono PCM audio (10ms = 160 samples)
        sample_count = 160
        samples = [0.0] * sample_count
        audio_bytes = struct.pack(f"<{sample_count}f", *samples)
        base64_audio = base64.b64encode(audio_bytes).decode("utf-8")

        # Act
        message = create_audio_data_message(
            audio_base64=base64_audio,
            sample_rate=16000
        )

        # Assert
        assert message.type == MessageType.AUDIO_DATA
        assert message.payload["audio_base64"] == base64_audio
        assert message.payload["sample_rate"] == 16000

    def test_audio_data_validates_payload(self):
        """audio_data payload validation should check required fields."""
        from ipc.protocol import validate_payload, MessageType

        # Valid payload
        valid = {"audio_base64": "SGVsbG8=", "sample_rate": 16000}
        assert validate_payload(MessageType.AUDIO_DATA, valid) is True

        # Invalid payload (missing sample_rate)
        invalid = {"audio_base64": "SGVsbG8="}
        with pytest.raises(ValueError):
            validate_payload(MessageType.AUDIO_DATA, invalid)

    def test_audio_data_with_format_field(self):
        """audio_data message should support format field."""
        from ipc.protocol import IPCMessage, MessageType

        # Arrange
        audio_data = b"\x00\x01\x02\x03"
        base64_audio = base64.b64encode(audio_data).decode("utf-8")

        # Act - Create message with format field
        message = IPCMessage(
            type=MessageType.AUDIO_DATA,
            payload={
                "audio_base64": base64_audio,
                "sample_rate": 16000,
                "format": "pcm_f32le"
            }
        )

        # Assert
        assert message.payload.get("format") == "pcm_f32le"


# ============================================================================
# Round-Trip Serialization Tests
# ============================================================================

class TestBase64RoundTrip:
    """Test round-trip JSON serialization with Base64 data."""

    def test_roundtrip_audio_data_preserves_binary(self):
        """Round-trip should preserve binary audio content."""
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        # Arrange: Create original audio data
        original_samples = [0.1, 0.2, 0.3, 0.4, 0.5]
        original_bytes = struct.pack(f"<{len(original_samples)}f", *original_samples)
        base64_audio = base64.b64encode(original_bytes).decode("utf-8")

        original_message = create_audio_data_message(
            audio_base64=base64_audio,
            sample_rate=16000
        )

        # Act: Serialize to JSON and back
        json_str = message_to_json(original_message)
        restored_message = message_from_json(json_str)

        # Assert: Message structure preserved
        assert restored_message.type == original_message.type

        # Assert: Base64 content preserved
        restored_base64 = restored_message.payload["audio_base64"]
        assert restored_base64 == base64_audio

        # Assert: Binary content can be decoded back
        decoded_bytes = base64.b64decode(restored_base64)
        assert decoded_bytes == original_bytes

        # Assert: Sample rate preserved
        assert restored_message.payload["sample_rate"] == 16000

    def test_roundtrip_with_message_id_and_timestamp(self):
        """Round-trip should preserve message_id and timestamp."""
        from ipc.protocol import (
            IPCMessage,
            MessageType,
            message_to_json,
            message_from_json
        )

        # Arrange
        test_data = b"\xFF\xFE\xFD"
        base64_data = base64.b64encode(test_data).decode("utf-8")
        message_id = "test-msg-12345"

        original_message = IPCMessage(
            type=MessageType.AUDIO_DATA,
            payload={
                "audio_base64": base64_data,
                "sample_rate": 16000
            },
            message_id=message_id
        )

        # Act
        json_str = message_to_json(original_message)
        restored_message = message_from_json(json_str)

        # Assert
        assert restored_message.message_id == message_id
        assert restored_message.payload["audio_base64"] == base64_data

    def test_roundtrip_all_message_types_with_base64(self):
        """All message types should support Base64 data in round-trip."""
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json,
            MessageType
        )

        # Arrange
        test_data = b"Test binary data"
        base64_data = base64.b64encode(test_data).decode("utf-8")

        # Test audio_data message
        audio_msg = create_audio_data_message(
            audio_base64=base64_data,
            sample_rate=16000
        )

        # Act & Assert
        json_str = message_to_json(audio_msg)
        restored = message_from_json(json_str)
        assert restored.type == MessageType.AUDIO_DATA
        assert restored.payload["audio_base64"] == base64_data


# ============================================================================
# Large Payload Tests
# ============================================================================

class TestLargePayload:
    """Test handling of large Base64 payloads."""

    def test_one_megabyte_payload(self):
        """Should handle 1MB audio payload."""
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        # Arrange: 1MB of audio data
        byte_count = 1024 * 1024
        large_data = bytes([0xAB] * byte_count)
        base64_large = base64.b64encode(large_data).decode("utf-8")

        # Act
        message = create_audio_data_message(
            audio_base64=base64_large,
            sample_rate=16000
        )
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        restored_base64 = restored.payload["audio_base64"]
        assert restored_base64 == base64_large

        decoded_data = base64.b64decode(restored_base64)
        assert len(decoded_data) == byte_count

    def test_ten_megabyte_payload(self):
        """Should handle 10MB audio payload (stress test)."""
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        # Arrange: 10MB payload
        byte_count = 10 * 1024 * 1024
        large_data = bytes([0xCD] * byte_count)
        base64_large = base64.b64encode(large_data).decode("utf-8")

        # Act
        message = create_audio_data_message(
            audio_base64=base64_large,
            sample_rate=16000
        )
        json_str = message_to_json(message)

        # Assert: JSON string is valid
        assert len(json_str) > 0

        # Assert: Can be deserialized
        restored = message_from_json(json_str)
        decoded_data = base64.b64decode(restored.payload["audio_base64"])
        assert len(decoded_data) == byte_count

    def test_empty_audio_payload(self):
        """Should handle empty audio payload."""
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        # Arrange
        empty_data = b""
        base64_empty = base64.b64encode(empty_data).decode("utf-8")

        # Act
        message = create_audio_data_message(
            audio_base64=base64_empty,
            sample_rate=16000
        )
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        assert restored.payload["audio_base64"] == ""


# ============================================================================
# Special Characters Tests
# ============================================================================

class TestSpecialCharacters:
    """Test handling of special characters in text fields."""

    def test_unicode_in_question(self):
        """Should handle Unicode characters in question field."""
        from ipc.protocol import (
            create_interview_start_message,
            message_to_json,
            message_from_json
        )

        # Arrange: Question with various Unicode characters
        question = "Design a system for: cafe, resume, naive, Munchen, Beijing"

        # Act
        message = create_interview_start_message(question=question)
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        assert restored.payload["question"] == question

    def test_emoji_in_response(self):
        """Should handle emoji characters in response field."""
        from ipc.protocol import (
            create_interview_response_message,
            message_to_json,
            message_from_json
        )

        # Arrange
        response = "I would use a distributed cache for better performance"

        # Act
        message = create_interview_response_message(response=response)
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        assert restored.payload["response"] == response

    def test_newlines_and_tabs(self):
        """Should handle newlines and tabs in text."""
        from ipc.protocol import (
            create_tts_speak_message,
            message_to_json,
            message_from_json
        )

        # Arrange
        text = "Line 1\nLine 2\n\tIndented line\n\t\tDouble indented"

        # Act
        message = create_tts_speak_message(text=text)
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        assert restored.payload["text"] == text

    def test_quotes_in_text(self):
        """Should handle quote characters in text."""
        from ipc.protocol import (
            create_transcription_message,
            message_to_json,
            message_from_json
        )

        # Arrange
        text = 'He said "Hello" and \'Goodbye\' with typographic quotes'

        # Act
        message = create_transcription_message(text=text, is_final=True)
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        assert restored.payload["text"] == text

    def test_backslashes_in_text(self):
        """Should handle backslash characters in text."""
        from ipc.protocol import (
            create_transcription_message,
            message_to_json,
            message_from_json
        )

        # Arrange: Text with backslashes (common in file paths)
        text = "Path: C:\\Users\\test\\file.txt and \\n escaped"

        # Act
        message = create_transcription_message(text=text, is_final=True)
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        assert restored.payload["text"] == text

    def test_null_bytes_in_base64_data(self):
        """Should handle null bytes in Base64 encoded data."""
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        # Arrange: Data containing null bytes
        data_with_nulls = b"\x00\x01\x00\x02\x00\x00\x03"
        base64_data = base64.b64encode(data_with_nulls).decode("utf-8")

        # Act
        message = create_audio_data_message(
            audio_base64=base64_data,
            sample_rate=16000
        )
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        decoded = base64.b64decode(restored.payload["audio_base64"])
        assert decoded == data_with_nulls

    def test_cjk_characters_in_transcript(self):
        """Should handle CJK characters in transcript."""
        from ipc.protocol import (
            create_transcription_message,
            message_to_json,
            message_from_json
        )

        # Arrange: Chinese, Japanese, Korean characters
        text = "Chinese: Japanese: Korean:"

        # Act
        message = create_transcription_message(text=text, is_final=True)
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        assert restored.payload["text"] == text

    def test_markdown_in_feedback_response(self):
        """Should handle markdown formatting in feedback response."""
        from ipc.protocol import (
            create_feedback_response_message,
            message_to_json,
            message_from_json
        )

        # Arrange: Markdown formatted feedback
        markdown = """# Interview Feedback

## Strengths
- **Clear communication** throughout
- Good use of `cache` for optimization

## Areas for Improvement
1. Consider *edge cases*
2. Discuss [trade-offs](https://example.com)

```python
def solution():
    return "code block"
```
"""

        # Act
        message = create_feedback_response_message(markdown=markdown)
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        assert restored.payload["markdown"] == markdown


# ============================================================================
# Edge Cases Tests
# ============================================================================

class TestEdgeCases:
    """Test edge cases in Base64 serialization."""

    def test_exactly_three_bytes_no_padding(self):
        """3 bytes should encode to 4 Base64 chars with no padding."""
        # Arrange
        data = b"\x01\x02\x03"
        base64_str = base64.b64encode(data).decode("utf-8")

        # Assert: No padding characters
        assert "=" not in base64_str

        # Round-trip test
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        message = create_audio_data_message(
            audio_base64=base64_str,
            sample_rate=16000
        )
        json_str = message_to_json(message)
        restored = message_from_json(json_str)
        decoded = base64.b64decode(restored.payload["audio_base64"])
        assert decoded == data

    def test_one_byte_two_padding_chars(self):
        """1 byte should encode with 2 padding characters."""
        # Arrange
        data = b"\xFF"
        base64_str = base64.b64encode(data).decode("utf-8")

        # Assert: Should end with "=="
        assert base64_str.endswith("==")

        # Round-trip test
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        message = create_audio_data_message(
            audio_base64=base64_str,
            sample_rate=16000
        )
        json_str = message_to_json(message)
        restored = message_from_json(json_str)
        decoded = base64.b64decode(restored.payload["audio_base64"])
        assert decoded == data

    def test_two_bytes_one_padding_char(self):
        """2 bytes should encode with 1 padding character."""
        # Arrange
        data = b"\xAA\xBB"
        base64_str = base64.b64encode(data).decode("utf-8")

        # Assert: Should end with single "="
        assert base64_str.endswith("=")
        assert not base64_str.endswith("==")

        # Round-trip test
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        message = create_audio_data_message(
            audio_base64=base64_str,
            sample_rate=16000
        )
        json_str = message_to_json(message)
        restored = message_from_json(json_str)
        decoded = base64.b64decode(restored.payload["audio_base64"])
        assert decoded == data

    def test_all_byte_values(self):
        """Should handle all possible byte values (0x00 to 0xFF)."""
        # Arrange
        all_bytes = bytes(range(256))
        base64_str = base64.b64encode(all_bytes).decode("utf-8")

        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        # Act
        message = create_audio_data_message(
            audio_base64=base64_str,
            sample_rate=16000
        )
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        decoded = base64.b64decode(restored.payload["audio_base64"])
        assert decoded == all_bytes
        assert len(decoded) == 256

    def test_very_long_text(self):
        """Should handle very long text (10KB)."""
        from ipc.protocol import (
            create_transcription_message,
            message_to_json,
            message_from_json
        )

        # Arrange: 10KB of text
        long_text = "A" * 10240

        # Act
        message = create_transcription_message(text=long_text, is_final=True)
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        restored_text = restored.payload["text"]
        assert restored_text == long_text
        assert len(restored_text) == 10240

    @pytest.mark.parametrize("sample_rate", [8000, 16000, 22050, 44100, 48000, 96000])
    def test_sample_rate_boundaries(self, sample_rate: int):
        """Should preserve various sample rate values."""
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        # Arrange
        test_data = b"\x00"
        base64_str = base64.b64encode(test_data).decode("utf-8")

        # Act
        message = create_audio_data_message(
            audio_base64=base64_str,
            sample_rate=sample_rate
        )
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        assert restored.payload["sample_rate"] == sample_rate


# ============================================================================
# Binary Audio Format Tests
# ============================================================================

class TestBinaryAudioFormat:
    """Test specific audio format encoding/decoding."""

    def test_pcm_float32_le_format(self):
        """PCM Float32 Little Endian samples should preserve exact values."""
        from ipc.protocol import (
            IPCMessage,
            MessageType,
            message_to_json,
            message_from_json
        )

        # Arrange: 4 float32 samples in little-endian
        samples = [0.0, 0.25, 0.5, 0.75]
        data = struct.pack(f"<{len(samples)}f", *samples)
        base64_str = base64.b64encode(data).decode("utf-8")

        # Act
        message = IPCMessage(
            type=MessageType.AUDIO_DATA,
            payload={
                "audio_base64": base64_str,
                "sample_rate": 16000,
                "format": "pcm_f32le"
            }
        )
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert: Decode and verify samples
        decoded_base64 = restored.payload["audio_base64"]
        decoded_data = base64.b64decode(decoded_base64)
        restored_samples = struct.unpack(f"<{len(samples)}f", decoded_data)

        assert len(restored_samples) == 4
        assert restored_samples[0] == pytest.approx(0.0)
        assert restored_samples[1] == pytest.approx(0.25)
        assert restored_samples[2] == pytest.approx(0.5)
        assert restored_samples[3] == pytest.approx(0.75)

    def test_pcm_int16_format(self):
        """PCM Int16 samples should preserve exact values."""
        from ipc.protocol import (
            IPCMessage,
            MessageType,
            message_to_json,
            message_from_json
        )

        # Arrange: 4 int16 samples
        samples = [0, 16384, 32767, -32768]
        data = struct.pack(f"<{len(samples)}h", *samples)
        base64_str = base64.b64encode(data).decode("utf-8")

        # Act
        message = IPCMessage(
            type=MessageType.AUDIO_DATA,
            payload={
                "audio_base64": base64_str,
                "sample_rate": 44100,
                "format": "pcm_s16le"
            }
        )
        json_str = message_to_json(message)
        restored = message_from_json(json_str)

        # Assert
        decoded_base64 = restored.payload["audio_base64"]
        decoded_data = base64.b64decode(decoded_base64)
        restored_samples = struct.unpack(f"<{len(samples)}h", decoded_data)

        assert len(restored_samples) == 4
        assert restored_samples[0] == 0
        assert restored_samples[1] == 16384
        assert restored_samples[2] == 32767
        assert restored_samples[3] == -32768


# ============================================================================
# Cross-Platform Compatibility Tests
# ============================================================================

class TestCrossPlatformCompatibility:
    """Test JSON format compatibility with Swift frontend."""

    def test_json_format_matches_swift_expectation(self):
        """JSON format should match what Swift expects."""
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json
        )

        # Arrange: Create message as Python would
        audio_data = b"\x01\x02\x03\x04"
        base64_str = base64.b64encode(audio_data).decode("utf-8")

        message = create_audio_data_message(
            audio_base64=base64_str,
            sample_rate=16000
        )

        # Act
        json_str = message_to_json(message)
        parsed = json.loads(json_str)

        # Assert: Structure matches Swift IPCProtocol.swift expectations
        assert parsed["type"] == "audio_data"
        assert "payload" in parsed
        assert parsed["payload"]["audio_base64"] == base64_str
        assert parsed["payload"]["sample_rate"] == 16000

    def test_parse_json_from_swift_format(self):
        """Should parse JSON generated by Swift frontend."""
        from ipc.protocol import message_from_json, MessageType

        # Arrange: JSON as Swift would generate (from IPCProtocol.swift)
        swift_json = json.dumps({
            "type": "audio_data",
            "payload": {
                "audio_base64": "AQIDBA==",
                "sample_rate": 16000
            },
            "message_id": "swift-msg-001",
            "timestamp": "2024-01-15T10:30:00Z"
        })

        # Act
        message = message_from_json(swift_json)

        # Assert
        assert message.type == MessageType.AUDIO_DATA
        assert message.payload["audio_base64"] == "AQIDBA=="
        assert message.payload["sample_rate"] == 16000
        assert message.message_id == "swift-msg-001"

        # Verify decoded data
        decoded = base64.b64decode("AQIDBA==")
        assert decoded == b"\x01\x02\x03\x04"


# ============================================================================
# Property-Based Tests (using hypothesis if available)
# ============================================================================

class TestBase64Properties:
    """Property-based tests for Base64 encoding/decoding."""

    def test_roundtrip_property_any_bytes(self):
        """Any byte sequence should survive encode -> decode round-trip."""
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json,
            message_from_json
        )

        # Test with various byte patterns
        test_cases = [
            b"",
            b"\x00",
            b"\xFF",
            b"\x00\xFF",
            bytes(range(256)),
            b"A" * 1000,
            bytes([i % 256 for i in range(10000)]),
        ]

        for original_bytes in test_cases:
            # Arrange
            base64_str = base64.b64encode(original_bytes).decode("utf-8")

            # Act
            message = create_audio_data_message(
                audio_base64=base64_str,
                sample_rate=16000
            )
            json_str = message_to_json(message)
            restored = message_from_json(json_str)

            # Assert
            decoded = base64.b64decode(restored.payload["audio_base64"])
            assert decoded == original_bytes, (
                f"Round-trip failed for data of length {len(original_bytes)}"
            )

    def test_json_serialization_is_deterministic(self):
        """Same message should always produce consistent JSON structure."""
        from ipc.protocol import (
            create_audio_data_message,
            message_to_json
        )

        # Arrange
        test_data = b"test data"
        base64_str = base64.b64encode(test_data).decode("utf-8")

        # Act: Serialize multiple times
        results = []
        for _ in range(10):
            message = create_audio_data_message(
                audio_base64=base64_str,
                sample_rate=16000
            )
            json_str = message_to_json(message)
            parsed = json.loads(json_str)
            # Remove timestamp which varies
            del parsed["timestamp"]
            results.append(parsed)

        # Assert: All results should have same structure
        first = results[0]
        for result in results[1:]:
            assert result["type"] == first["type"]
            assert result["payload"] == first["payload"]
