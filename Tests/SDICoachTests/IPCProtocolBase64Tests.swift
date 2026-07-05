// Tests for IPC Protocol Base64 Serialization
//
// Task 1.1.2: JSON serialization with Base64 support
//
// These tests verify:
// 1. Base64 encoding of binary audio data
// 2. Base64 decoding of audio data
// 3. Round-trip serialization with binary payload
// 4. Large payload handling
// 5. Special characters in text fields
//
// Expected to FAIL until implementation is complete (RED phase).

import Testing
import Foundation
@testable import SDICoach

// MARK: - Base64 Encoding Tests

@Suite("Base64 Encoding Tests")
struct Base64EncodingTests {

    // MARK: Test: Basic byte array to Base64 encoding

    @Test("encode empty byte array to Base64")
    func testEncodeEmptyData() throws {
        // Arrange
        let emptyData = Data()

        // Act
        // This test expects a utility function: Data.base64EncodedForIPC() -> String
        // Currently DOES NOT EXIST - will fail
        let encoded = emptyData.base64EncodedString()

        // Assert
        #expect(encoded == "")
    }

    @Test("encode single byte to Base64")
    func testEncodeSingleByte() throws {
        // Arrange: Single byte 0x00
        let data = Data([0x00])

        // Act
        let encoded = data.base64EncodedString()

        // Assert: Single null byte encodes to "AA=="
        #expect(encoded == "AA==")
    }

    @Test("encode Hello World to Base64")
    func testEncodeHelloWorld() throws {
        // Arrange
        let text = "Hello World"
        let data = text.data(using: .utf8)!

        // Act
        let encoded = data.base64EncodedString()

        // Assert
        #expect(encoded == "SGVsbG8gV29ybGQ=")
    }

    @Test("encode PCM audio samples to Base64")
    func testEncodePCMAudioSamples() throws {
        // Arrange: 4 float32 samples representing PCM audio
        // These are little-endian float32 values: 0.0, 0.5, -0.5, 1.0
        var samples: [Float32] = [0.0, 0.5, -0.5, 1.0]
        let data = Data(bytes: &samples, count: samples.count * MemoryLayout<Float32>.size)

        // Act
        let encoded = data.base64EncodedString()

        // Assert: The encoded string should be valid Base64
        #expect(!encoded.isEmpty)
        // Verify round-trip
        let decoded = Data(base64Encoded: encoded)
        #expect(decoded == data)
    }
}

// MARK: - Base64 Decoding Tests

@Suite("Base64 Decoding Tests")
struct Base64DecodingTests {

    @Test("decode empty Base64 string")
    func testDecodeEmptyString() throws {
        // Arrange
        let encoded = ""

        // Act
        let decoded = Data(base64Encoded: encoded)

        // Assert
        #expect(decoded == Data())
    }

    @Test("decode Hello World from Base64")
    func testDecodeHelloWorld() throws {
        // Arrange
        let encoded = "SGVsbG8gV29ybGQ="

        // Act
        let decoded = Data(base64Encoded: encoded)

        // Assert
        #expect(decoded != nil)
        let text = String(data: decoded!, encoding: .utf8)
        #expect(text == "Hello World")
    }

    @Test("decode invalid Base64 returns nil")
    func testDecodeInvalidBase64() throws {
        // Arrange: Invalid Base64 (contains invalid characters)
        let invalid = "!@#$%^&*()"

        // Act
        let decoded = Data(base64Encoded: invalid)

        // Assert
        #expect(decoded == nil)
    }

    @Test("decode Base64 with padding")
    func testDecodeWithPadding() throws {
        // Arrange: "A" -> "QQ=="
        let encoded = "QQ=="

        // Act
        let decoded = Data(base64Encoded: encoded)

        // Assert
        #expect(decoded != nil)
        let text = String(data: decoded!, encoding: .utf8)
        #expect(text == "A")
    }

    @Test("decode Base64 without padding")
    func testDecodeWithoutPadding() throws {
        // Arrange: "QQ==" without padding = "QQ"
        let encoded = "QQ"

        // Act - Use the helper that adds padding automatically
        let decoded = Data(base64EncodedWithPadding: encoded, options: .ignoreUnknownCharacters)

        // Assert
        #expect(decoded != nil)
    }
}

// MARK: - AudioData Message Tests

@Suite("AudioData Base64 Message Tests")
struct AudioDataBase64Tests {

    @Test("create audio_data message with Base64 encoded audio")
    func testCreateAudioDataMessage() throws {
        // Arrange: Simulate 16kHz mono PCM audio (1 second = 16000 samples)
        let sampleCount = 160  // 10ms of audio at 16kHz
        var samples = [Float32](repeating: 0.0, count: sampleCount)
        // Generate simple sine wave
        for i in 0..<sampleCount {
            samples[i] = sin(Float32(i) * 0.1)
        }
        let audioData = Data(bytes: &samples, count: samples.count * MemoryLayout<Float32>.size)
        let base64Audio = audioData.base64EncodedString()

        // Act
        let message = IPCMessage.audioData(audioBase64: base64Audio, sampleRate: 16000)

        // Assert
        #expect(message.type == .audioData)
        #expect(message.payload["audio_base64"]?.value as? String == base64Audio)
        #expect(message.payload["sample_rate"]?.value as? Int == 16000)
    }

    @Test("audio_data message validates payload structure")
    func testAudioDataValidation() throws {
        // Arrange: Valid payload
        let validPayload: [String: AnyCodable] = [
            "audio_base64": AnyCodable("SGVsbG8="),
            "sample_rate": AnyCodable(16000)
        ]

        // Act & Assert
        #expect(MessageType.audioData.validatePayload(validPayload) == true)

        // Arrange: Invalid payload (missing sample_rate)
        let invalidPayload: [String: AnyCodable] = [
            "audio_base64": AnyCodable("SGVsbG8=")
        ]

        // Act & Assert
        #expect(MessageType.audioData.validatePayload(invalidPayload) == false)
    }

    @Test("audio_data message includes format field")
    func testAudioDataWithFormat() throws {
        // Arrange
        let audioData = Data([0x00, 0x01, 0x02, 0x03])
        let base64Audio = audioData.base64EncodedString()

        // Act
        // This test expects an extended factory function that accepts format parameter
        // IPCMessage.audioData(audioBase64:sampleRate:format:) - DOES NOT EXIST YET
        let message = IPCMessage(
            type: .audioData,
            payload: [
                "audio_base64": AnyCodable(base64Audio),
                "sample_rate": AnyCodable(16000),
                "format": AnyCodable("pcm_f32le")
            ]
        )

        // Assert
        #expect(message.payload["format"]?.value as? String == "pcm_f32le")
    }
}

// MARK: - Round-Trip Serialization Tests

@Suite("Base64 Round-Trip Serialization Tests")
struct Base64RoundTripTests {

    @Test("round-trip audio_data message preserves binary content")
    func testRoundTripAudioData() throws {
        // Arrange: Create original audio data
        var originalSamples: [Float32] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let originalData = Data(bytes: &originalSamples, count: originalSamples.count * MemoryLayout<Float32>.size)
        let base64Audio = originalData.base64EncodedString()

        let originalMessage = IPCMessage.audioData(audioBase64: base64Audio, sampleRate: 16000)

        // Act: Serialize to JSON and back
        let jsonString = try originalMessage.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert: Message structure preserved
        #expect(restoredMessage.type == originalMessage.type)

        // Assert: Base64 content preserved
        let restoredBase64 = restoredMessage.payload["audio_base64"]?.value as? String
        #expect(restoredBase64 == base64Audio)

        // Assert: Binary content can be decoded back
        let decodedData = Data(base64Encoded: restoredBase64!)
        #expect(decodedData == originalData)

        // Assert: Sample rate preserved
        let restoredSampleRate = restoredMessage.payload["sample_rate"]?.value as? Int
        #expect(restoredSampleRate == 16000)
    }

    @Test("round-trip preserves all message types with Base64 payload")
    func testRoundTripAllMessageTypes() throws {
        // Arrange: Test data
        let testData = "Test binary data".data(using: .utf8)!
        let base64Data = testData.base64EncodedString()

        // Audio data message
        let audioMsg = IPCMessage.audioData(audioBase64: base64Data, sampleRate: 16000)

        // Act & Assert for audio_data
        let audioJson = try audioMsg.toJSONString()
        let restoredAudio = try IPCMessage.fromJSONString(audioJson)
        #expect(restoredAudio.type == .audioData)
        #expect(restoredAudio.payload["audio_base64"]?.value as? String == base64Data)
    }

    @Test("round-trip with message_id and timestamp")
    func testRoundTripWithMetadata() throws {
        // Arrange
        let testData = Data([0xFF, 0xFE, 0xFD])
        let base64Data = testData.base64EncodedString()
        let messageId = "test-msg-12345"

        let originalMessage = IPCMessage(
            type: .audioData,
            payload: [
                "audio_base64": AnyCodable(base64Data),
                "sample_rate": AnyCodable(16000)
            ],
            messageId: messageId
        )

        // Act
        let jsonString = try originalMessage.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        #expect(restoredMessage.messageId == messageId)
        #expect(restoredMessage.payload["audio_base64"]?.value as? String == base64Data)
    }
}

// MARK: - Large Payload Tests

@Suite("Large Payload Tests")
struct LargePayloadTests {

    @Test("handle 1MB audio payload")
    func testOneMegabytePayload() throws {
        // Arrange: 1MB of audio data (approximately 16 seconds at 16kHz stereo float32)
        let byteCount = 1024 * 1024  // 1 MB
        let largeData = Data(repeating: 0xAB, count: byteCount)
        let base64Large = largeData.base64EncodedString()

        // Act
        let message = IPCMessage.audioData(audioBase64: base64Large, sampleRate: 16000)
        let jsonString = try message.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        let restoredBase64 = restoredMessage.payload["audio_base64"]?.value as? String
        #expect(restoredBase64 == base64Large)

        let decodedData = Data(base64Encoded: restoredBase64!)
        #expect(decodedData?.count == byteCount)
    }

    @Test("handle 10MB audio payload")
    func testTenMegabytePayload() throws {
        // Arrange: 10MB payload (stress test)
        let byteCount = 10 * 1024 * 1024
        let largeData = Data(repeating: 0xCD, count: byteCount)
        let base64Large = largeData.base64EncodedString()

        // Act
        let message = IPCMessage.audioData(audioBase64: base64Large, sampleRate: 16000)
        let jsonString = try message.toJSONString()

        // Assert: JSON string is valid
        #expect(!jsonString.isEmpty)

        // Assert: Can be deserialized
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)
        let restoredBase64 = restoredMessage.payload["audio_base64"]?.value as? String

        // Assert: Data integrity
        let decodedData = Data(base64Encoded: restoredBase64!)
        #expect(decodedData?.count == byteCount)
    }

    @Test("handle empty audio payload")
    func testEmptyPayload() throws {
        // Arrange
        let emptyData = Data()
        let base64Empty = emptyData.base64EncodedString()

        // Act
        let message = IPCMessage.audioData(audioBase64: base64Empty, sampleRate: 16000)
        let jsonString = try message.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        let restoredBase64 = restoredMessage.payload["audio_base64"]?.value as? String
        #expect(restoredBase64 == "")
    }
}

// MARK: - Special Characters Tests

@Suite("Special Characters in Text Fields Tests")
struct SpecialCharactersTests {

    @Test("handle Unicode characters in question field")
    func testUnicodeInQuestion() throws {
        // Arrange: Question with various Unicode characters
        let question = "Design a system for: cafe, resume, naive, Munchen, Beijing"

        // Act
        let message = IPCMessage.interviewStart(question: question)
        let jsonString = try message.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        let restoredQuestion = restoredMessage.payload["question"]?.value as? String
        #expect(restoredQuestion == question)
    }

    @Test("handle emoji in response field")
    func testEmojiInResponse() throws {
        // Arrange: Response with emojis
        let response = "I would use a distributed cache for better performance"

        // Act
        let message = IPCMessage.interviewResponse(response: response)
        let jsonString = try message.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        #expect(restoredMessage.payload["response"]?.value as? String == response)
    }

    @Test("handle newlines and tabs in text")
    func testNewlinesAndTabs() throws {
        // Arrange: Text with newlines and tabs
        let text = "Line 1\nLine 2\n\tIndented line\n\t\tDouble indented"

        // Act
        let message = IPCMessage.ttsSpeak(text: text)
        let jsonString = try message.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        #expect(restoredMessage.payload["text"]?.value as? String == text)
    }

    @Test("handle quotes in text")
    func testQuotesInText() throws {
        // Arrange: Text with various quote characters
        let text = "He said \"Hello\" and 'Goodbye' with typographic quotes"

        // Act
        let message = IPCMessage.transcription(text: text, isFinal: true)
        let jsonString = try message.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        #expect(restoredMessage.payload["text"]?.value as? String == text)
    }

    @Test("handle backslashes in text")
    func testBackslashesInText() throws {
        // Arrange: Text with backslashes (common in file paths)
        let text = "Path: C:\\Users\\test\\file.txt and \\n escaped"

        // Act
        let message = IPCMessage.transcription(text: text, isFinal: true)
        let jsonString = try message.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        #expect(restoredMessage.payload["text"]?.value as? String == text)
    }

    @Test("handle null bytes in Base64 encoded data")
    func testNullBytesInData() throws {
        // Arrange: Data containing null bytes
        let dataWithNulls = Data([0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x03])
        let base64Data = dataWithNulls.base64EncodedString()

        // Act
        let message = IPCMessage.audioData(audioBase64: base64Data, sampleRate: 16000)
        let jsonString = try message.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        let restoredBase64 = restoredMessage.payload["audio_base64"]?.value as? String
        let decodedData = Data(base64Encoded: restoredBase64!)
        #expect(decodedData == dataWithNulls)
    }

    @Test("handle CJK characters in transcript")
    func testCJKCharacters() throws {
        // Arrange: Chinese, Japanese, Korean characters
        let text = "Chinese: Japanese: Korean:"

        // Act
        let message = IPCMessage.transcription(text: text, isFinal: true)
        let jsonString = try message.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        #expect(restoredMessage.payload["text"]?.value as? String == text)
    }

    @Test("handle markdown in feedback response")
    func testMarkdownInFeedback() throws {
        // Arrange: Markdown formatted feedback
        let markdown = """
        # Interview Feedback

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

        // Act
        let message = IPCMessage.feedbackResponse(markdown: markdown)
        let jsonString = try message.toJSONString()
        let restoredMessage = try IPCMessage.fromJSONString(jsonString)

        // Assert
        #expect(restoredMessage.payload["markdown"]?.value as? String == markdown)
    }
}

// MARK: - Edge Cases Tests

@Suite("Edge Cases Tests")
struct EdgeCasesTests {

    @Test("handle exactly 3 bytes (no padding needed)")
    func testExactlyThreeBytes() throws {
        // Arrange: 3 bytes encode to exactly 4 Base64 characters (no padding)
        let data = Data([0x01, 0x02, 0x03])
        let base64 = data.base64EncodedString()

        // Assert: No padding characters
        #expect(!base64.contains("="))

        // Round-trip
        let message = IPCMessage.audioData(audioBase64: base64, sampleRate: 16000)
        let jsonString = try message.toJSONString()
        let restored = try IPCMessage.fromJSONString(jsonString)
        let decodedData = Data(base64Encoded: restored.payload["audio_base64"]?.value as! String)
        #expect(decodedData == data)
    }

    @Test("handle 1 byte (2 padding chars)")
    func testOneByte() throws {
        // Arrange: 1 byte encodes to 4 Base64 chars with 2 padding
        let data = Data([0xFF])
        let base64 = data.base64EncodedString()

        // Assert: Should end with "=="
        #expect(base64.hasSuffix("=="))

        // Round-trip
        let message = IPCMessage.audioData(audioBase64: base64, sampleRate: 16000)
        let jsonString = try message.toJSONString()
        let restored = try IPCMessage.fromJSONString(jsonString)
        let decodedData = Data(base64Encoded: restored.payload["audio_base64"]?.value as! String)
        #expect(decodedData == data)
    }

    @Test("handle 2 bytes (1 padding char)")
    func testTwoBytes() throws {
        // Arrange: 2 bytes encode to 4 Base64 chars with 1 padding
        let data = Data([0xAA, 0xBB])
        let base64 = data.base64EncodedString()

        // Assert: Should end with single "="
        #expect(base64.hasSuffix("="))
        #expect(!base64.hasSuffix("=="))

        // Round-trip
        let message = IPCMessage.audioData(audioBase64: base64, sampleRate: 16000)
        let jsonString = try message.toJSONString()
        let restored = try IPCMessage.fromJSONString(jsonString)
        let decodedData = Data(base64Encoded: restored.payload["audio_base64"]?.value as! String)
        #expect(decodedData == data)
    }

    @Test("handle all byte values 0x00 to 0xFF")
    func testAllByteValues() throws {
        // Arrange: Data containing all possible byte values
        var allBytes = Data()
        for i in 0...255 {
            allBytes.append(UInt8(i))
        }
        let base64 = allBytes.base64EncodedString()

        // Act
        let message = IPCMessage.audioData(audioBase64: base64, sampleRate: 16000)
        let jsonString = try message.toJSONString()
        let restored = try IPCMessage.fromJSONString(jsonString)

        // Assert
        let decodedData = Data(base64Encoded: restored.payload["audio_base64"]?.value as! String)
        #expect(decodedData == allBytes)
        #expect(decodedData?.count == 256)
    }

    @Test("handle very long single line of text")
    func testVeryLongText() throws {
        // Arrange: 10KB of text
        let longText = String(repeating: "A", count: 10240)

        // Act
        let message = IPCMessage.transcription(text: longText, isFinal: true)
        let jsonString = try message.toJSONString()
        let restored = try IPCMessage.fromJSONString(jsonString)

        // Assert
        let restoredText = restored.payload["text"]?.value as? String
        #expect(restoredText == longText)
        #expect(restoredText?.count == 10240)
    }

    @Test("handle sample rate boundary values")
    func testSampleRateBoundaries() throws {
        // Arrange: Test various sample rates
        let sampleRates = [8000, 16000, 22050, 44100, 48000, 96000]
        let testData = Data([0x00])
        let base64 = testData.base64EncodedString()

        for sampleRate in sampleRates {
            // Act
            let message = IPCMessage.audioData(audioBase64: base64, sampleRate: sampleRate)
            let jsonString = try message.toJSONString()
            let restored = try IPCMessage.fromJSONString(jsonString)

            // Assert
            let restoredRate = restored.payload["sample_rate"]?.value as? Int
            #expect(restoredRate == sampleRate, "Sample rate \(sampleRate) should be preserved")
        }
    }
}

// MARK: - Binary Audio Format Tests

@Suite("Binary Audio Format Tests")
struct BinaryAudioFormatTests {

    @Test("PCM Float32 Little Endian format")
    func testPCMFloat32LE() throws {
        // Arrange: 4 float32 samples in little-endian
        var samples: [Float32] = [0.0, 0.25, 0.5, 0.75]
        let data = Data(bytes: &samples, count: samples.count * MemoryLayout<Float32>.size)
        let base64 = data.base64EncodedString()

        // Act
        let message = IPCMessage(
            type: .audioData,
            payload: [
                "audio_base64": AnyCodable(base64),
                "sample_rate": AnyCodable(16000),
                "format": AnyCodable("pcm_f32le")
            ]
        )
        let jsonString = try message.toJSONString()
        let restored = try IPCMessage.fromJSONString(jsonString)

        // Assert: Decode and verify samples
        let decodedBase64 = restored.payload["audio_base64"]?.value as! String
        let decodedData = Data(base64Encoded: decodedBase64)!

        // Convert back to float32 array
        let restoredSamples = decodedData.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float32.self))
        }

        #expect(restoredSamples.count == 4)
        #expect(restoredSamples[0] == 0.0)
        #expect(restoredSamples[1] == 0.25)
        #expect(restoredSamples[2] == 0.5)
        #expect(restoredSamples[3] == 0.75)
    }

    @Test("PCM Int16 format")
    func testPCMInt16() throws {
        // Arrange: 4 int16 samples
        var samples: [Int16] = [0, 16384, 32767, -32768]
        let data = Data(bytes: &samples, count: samples.count * MemoryLayout<Int16>.size)
        let base64 = data.base64EncodedString()

        // Act
        let message = IPCMessage(
            type: .audioData,
            payload: [
                "audio_base64": AnyCodable(base64),
                "sample_rate": AnyCodable(44100),
                "format": AnyCodable("pcm_s16le")
            ]
        )
        let jsonString = try message.toJSONString()
        let restored = try IPCMessage.fromJSONString(jsonString)

        // Assert
        let decodedBase64 = restored.payload["audio_base64"]?.value as! String
        let decodedData = Data(base64Encoded: decodedBase64)!

        let restoredSamples = decodedData.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Int16.self))
        }

        #expect(restoredSamples.count == 4)
        #expect(restoredSamples[0] == 0)
        #expect(restoredSamples[1] == 16384)
        #expect(restoredSamples[2] == 32767)
        #expect(restoredSamples[3] == -32768)
    }
}

// MARK: - Cross-Platform Compatibility Tests

@Suite("Cross-Platform Compatibility Tests")
struct CrossPlatformCompatibilityTests {

    @Test("JSON format matches Python backend expectation")
    func testJSONFormatForPythonBackend() throws {
        // Arrange: Create message as Swift would
        let audioData = Data([0x01, 0x02, 0x03, 0x04])
        let base64 = audioData.base64EncodedString()

        let message = IPCMessage.audioData(audioBase64: base64, sampleRate: 16000)

        // Act
        let jsonString = try message.toJSONString()
        let jsonData = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        // Assert: Structure matches Python protocol.py expectations
        #expect(json["type"] as? String == "audio_data")

        let payload = json["payload"] as! [String: Any]
        #expect(payload["audio_base64"] as? String == base64)
        #expect(payload["sample_rate"] as? Int == 16000)
    }

    @Test("parse JSON from Python backend format")
    func testParseFromPythonBackend() throws {
        // Arrange: JSON as Python would generate (from protocol.py)
        let pythonJSON = """
        {
            "type": "audio_data",
            "payload": {
                "audio_base64": "AQIDBA==",
                "sample_rate": 16000
            },
            "message_id": "py-msg-001",
            "timestamp": "2024-01-15T10:30:00"
        }
        """

        // Act
        let message = try IPCMessage.fromJSONString(pythonJSON)

        // Assert
        #expect(message.type == .audioData)
        #expect(message.payload["audio_base64"]?.value as? String == "AQIDBA==")
        #expect(message.payload["sample_rate"]?.value as? Int == 16000)
        #expect(message.messageId == "py-msg-001")

        // Verify decoded data
        let decodedData = Data(base64Encoded: "AQIDBA==")
        #expect(decodedData == Data([0x01, 0x02, 0x03, 0x04]))
    }
}
