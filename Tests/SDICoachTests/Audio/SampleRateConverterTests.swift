import Testing
import Foundation
@testable import SDICoach

// MARK: - Test Suite: 2.2.1 vDSP Resampling (48kHz -> 16kHz)

@Suite("SampleRateConverter: vDSP Resampling")
struct SampleRateConverterResamplingTests {

    @Test("Basic conversion 48kHz to 16kHz")
    func basicConversion48To16() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // Create 48 samples at 48kHz (1ms of audio)
        let inputSamples = [Float](repeating: 0.5, count: 48)
        let buffer = AudioBuffer(
            samples: inputSamples,
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert
        #expect(result.sampleRate == 16000)
        // 48 samples at 48kHz -> 16 samples at 16kHz (ratio 3:1)
        #expect(result.samples.count == 16)
        #expect(result.source == .microphone)
    }

    @Test("Conversion ratio is correct (3:1)")
    func conversionRatioIs3To1() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // Assert
        #expect(converter.ratio == 3.0)
    }

    @Test("Output sample count matches expected formula")
    func outputSampleCountMatchesFormula() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // Test various input sizes
        let testCases = [
            (input: 48, expected: 16),     // Exact multiple
            (input: 96, expected: 32),     // Exact multiple
            (input: 480, expected: 160),   // 10ms of audio
            (input: 4800, expected: 1600), // 100ms of audio
            (input: 49, expected: 16),     // Slightly over (floor division)
            (input: 50, expected: 16),     // Slightly over
            (input: 47, expected: 15),     // Slightly under
        ]

        for testCase in testCases {
            let inputSamples = [Float](repeating: 0.5, count: testCase.input)
            let buffer = AudioBuffer(
                samples: inputSamples,
                sampleRate: 48000,
                timestamp: Date(),
                source: .microphone
            )

            let result = converter.convert(buffer: buffer)
            #expect(result.samples.count == testCase.expected,
                    "Input \(testCase.input) samples should produce \(testCase.expected) output samples, got \(result.samples.count)")
        }
    }

    @Test("expectedOutputCount calculation is correct")
    func expectedOutputCountCalculation() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // Assert
        #expect(converter.expectedOutputCount(for: 48) == 16)
        #expect(converter.expectedOutputCount(for: 96) == 32)
        #expect(converter.expectedOutputCount(for: 480) == 160)
        #expect(converter.expectedOutputCount(for: 4800) == 1600)
    }

    @Test("expectedOutputCount with custom input rate")
    func expectedOutputCountCustomRate() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // Assert - 44100 to 16000 (ratio ~2.756)
        #expect(converter.expectedOutputCount(for: 44100, inputRate: 44100) == 16000)
        #expect(converter.expectedOutputCount(for: 441, inputRate: 44100) == 160)
    }

    @Test("Timestamp is preserved after conversion")
    func timestampIsPreserved() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)
        let timestamp = Date()
        let buffer = AudioBuffer(
            samples: [Float](repeating: 0.5, count: 48),
            sampleRate: 48000,
            timestamp: timestamp,
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert
        #expect(result.timestamp == timestamp)
    }

    @Test("Source is preserved after conversion")
    func sourceIsPreserved() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // Test microphone source
        let micBuffer = AudioBuffer(
            samples: [Float](repeating: 0.5, count: 48),
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )
        let micResult = converter.convert(buffer: micBuffer)
        #expect(micResult.source == .microphone)

        // Test system source
        let sysBuffer = AudioBuffer(
            samples: [Float](repeating: 0.5, count: 48),
            sampleRate: 48000,
            timestamp: Date(),
            source: .system
        )
        let sysResult = converter.convert(buffer: sysBuffer)
        #expect(sysResult.source == .system)
    }
}

// MARK: - Test Suite: 2.2.2 Buffer Management

@Suite("SampleRateConverter: Buffer Management")
struct SampleRateConverterBufferTests {

    @Test("Empty buffer returns empty buffer")
    func emptyBufferHandling() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)
        let buffer = AudioBuffer(
            samples: [],
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert
        #expect(result.samples.isEmpty)
        #expect(result.sampleRate == 16000)
    }

    @Test("Single sample produces no output (too small)")
    func singleSampleHandling() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)
        let buffer = AudioBuffer(
            samples: [0.5],
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert - 1 sample / 3 ratio = 0 output samples (floor division)
        #expect(result.samples.isEmpty)
    }

    @Test("Three samples produce one output sample")
    func threeSamplesProduceOne() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)
        let buffer = AudioBuffer(
            samples: [0.3, 0.5, 0.7],
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert
        #expect(result.samples.count == 1)
    }

    @Test("Large buffer handling (10 seconds of audio)")
    func largeBufferHandling() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // 10 seconds at 48kHz = 480,000 samples
        let inputSamples = [Float](repeating: 0.5, count: 480_000)
        let buffer = AudioBuffer(
            samples: inputSamples,
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert - 10 seconds at 16kHz = 160,000 samples
        #expect(result.samples.count == 160_000)
    }

    @Test("Buffer with various input sizes")
    func variousInputSizes() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        let sizes = [10, 100, 1000, 4096, 8192, 16384]

        for size in sizes {
            let buffer = AudioBuffer(
                samples: [Float](repeating: 0.5, count: size),
                sampleRate: 48000,
                timestamp: Date(),
                source: .microphone
            )

            let result = converter.convert(buffer: buffer)
            let expectedCount = size / 3

            #expect(result.samples.count == expectedCount,
                    "Size \(size) should produce \(expectedCount) samples, got \(result.samples.count)")
        }
    }
}

// MARK: - Test Suite: Passthrough Behavior

@Suite("SampleRateConverter: Passthrough")
struct SampleRateConverterPassthroughTests {

    @Test("Passthrough when rates match")
    func passthroughWhenRatesMatch() {
        // Arrange
        let converter = SampleRateConverter(from: 16000, to: 16000)
        let inputSamples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let buffer = AudioBuffer(
            samples: inputSamples,
            sampleRate: 16000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert - samples should be unchanged
        #expect(result.samples.count == inputSamples.count)
        #expect(result.samples == inputSamples)
        #expect(result.sampleRate == 16000)
    }

    @Test("Passthrough when buffer rate matches output rate")
    func passthroughWhenBufferRateMatches() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)
        let inputSamples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        // Buffer already at target rate
        let buffer = AudioBuffer(
            samples: inputSamples,
            sampleRate: 16000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert - no conversion needed, passthrough
        #expect(result.samples.count == inputSamples.count)
        #expect(result.samples == inputSamples)
    }
}

// MARK: - Test Suite: Low-Pass Filter (Anti-Aliasing)

@Suite("SampleRateConverter: Anti-Aliasing Filter")
struct SampleRateConverterFilterTests {

    @Test("Low-pass filter attenuates high frequencies")
    func lowPassFilterAttenuatesHighFrequencies() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // Create high-frequency signal (alternating samples)
        // This represents frequency at Nyquist (24kHz at 48kHz sample rate)
        var highFreqSamples = [Float]()
        for i in 0..<96 {
            highFreqSamples.append(i % 2 == 0 ? 1.0 : -1.0)
        }

        let buffer = AudioBuffer(
            samples: highFreqSamples,
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert - high frequency content should be significantly reduced
        // After low-pass filtering and decimation, alternating pattern should be smoothed
        let maxAbsValue = result.samples.map { abs($0) }.max() ?? 0

        // The high frequency should be attenuated (not preserved as full +/-1.0)
        #expect(maxAbsValue < 1.0,
                "High frequency should be attenuated, but max value is \(maxAbsValue)")
    }

    @Test("Low-frequency signal is preserved")
    func lowFrequencySignalPreserved() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // Create low-frequency sine wave (1kHz at 48kHz = 48 samples per cycle)
        var lowFreqSamples = [Float]()
        let samplesPerCycle = 48
        let numCycles = 10

        for i in 0..<(samplesPerCycle * numCycles) {
            let phase = Float(i) / Float(samplesPerCycle) * 2 * .pi
            lowFreqSamples.append(sin(phase))
        }

        let buffer = AudioBuffer(
            samples: lowFreqSamples,
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert - low frequency signal should have similar amplitude
        let inputSquaredSum = lowFreqSamples.map { $0 * $0 }.reduce(0, +)
        let inputRMS = sqrt(inputSquaredSum / Float(lowFreqSamples.count))
        let outputSquaredSum = result.samples.map { $0 * $0 }.reduce(0, +)
        let outputRMS = sqrt(outputSquaredSum / Float(result.samples.count))

        // RMS should be approximately preserved (within 20%)
        let rmsRatio = outputRMS / inputRMS
        #expect(rmsRatio > 0.8 && rmsRatio < 1.2,
                "Low frequency RMS should be preserved. Input RMS: \(inputRMS), Output RMS: \(outputRMS), Ratio: \(rmsRatio)")
    }

    @Test("DC signal is preserved")
    func dcSignalPreserved() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // DC signal (constant value)
        let dcValue: Float = 0.75
        let buffer = AudioBuffer(
            samples: [Float](repeating: dcValue, count: 480),
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert - DC should be preserved
        let outputMean = result.samples.reduce(0, +) / Float(result.samples.count)
        #expect(abs(outputMean - dcValue) < 0.1,
                "DC value should be preserved. Expected \(dcValue), got \(outputMean)")
    }
}

// MARK: - Test Suite: AudioBuffer Extension

@Suite("SampleRateConverter: AudioBuffer Extension")
struct AudioBufferConversionExtensionTests {

    @Test("AudioBuffer.converted(to:) extension works")
    func audioBufferConvertedExtension() {
        // Arrange
        let buffer = AudioBuffer(
            samples: [Float](repeating: 0.5, count: 48),
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = buffer.converted(to: 16000)

        // Assert
        #expect(result.sampleRate == 16000)
        #expect(result.samples.count == 16)
    }

    @Test("AudioBuffer.converted preserves metadata")
    func convertedPreservesMetadata() {
        // Arrange
        let timestamp = Date()
        let buffer = AudioBuffer(
            samples: [Float](repeating: 0.5, count: 48),
            sampleRate: 48000,
            timestamp: timestamp,
            source: .system
        )

        // Act
        let result = buffer.converted(to: 16000)

        // Assert
        #expect(result.timestamp == timestamp)
        #expect(result.source == .system)
    }

    @Test("AudioBuffer.converted with same rate returns unchanged")
    func convertedSameRateUnchanged() {
        // Arrange
        let samples: [Float] = [0.1, 0.2, 0.3]
        let buffer = AudioBuffer(
            samples: samples,
            sampleRate: 16000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = buffer.converted(to: 16000)

        // Assert
        #expect(result.samples == samples)
    }
}

// MARK: - Test Suite: Edge Cases

@Suite("SampleRateConverter: Edge Cases")
struct SampleRateConverterEdgeCaseTests {

    @Test("Handles extreme sample values")
    func handlesExtremeSampleValues() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // Include extreme values
        var samples = [Float](repeating: 0, count: 48)
        samples[0] = Float.greatestFiniteMagnitude / 2
        samples[1] = -Float.greatestFiniteMagnitude / 2
        samples[2] = Float.leastNormalMagnitude
        samples[3] = -Float.leastNormalMagnitude
        samples[4] = 0

        let buffer = AudioBuffer(
            samples: samples,
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert - should not crash and produce valid output
        #expect(result.samples.count == 16)
        #expect(result.samples.allSatisfy { $0.isFinite })
    }

    @Test("Handles buffer with NaN values gracefully")
    func handlesNaNValues() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        var samples = [Float](repeating: 0.5, count: 48)
        samples[10] = Float.nan

        let buffer = AudioBuffer(
            samples: samples,
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert - should produce output (behavior with NaN is implementation-defined)
        #expect(result.samples.count == 16)
    }

    @Test("Default initializer uses 48kHz to 16kHz")
    func defaultInitializer() {
        // Arrange & Act
        let converter = SampleRateConverter()

        // Assert
        #expect(converter.inputSampleRate == 48000)
        #expect(converter.outputSampleRate == 16000)
        #expect(converter.ratio == 3.0)
    }

    @Test("Custom sample rates work correctly")
    func customSampleRates() {
        // Arrange - 44100 to 22050 (2:1 ratio)
        let converter = SampleRateConverter(from: 44100, to: 22050)

        let buffer = AudioBuffer(
            samples: [Float](repeating: 0.5, count: 44),
            sampleRate: 44100,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert
        #expect(result.sampleRate == 22050)
        #expect(result.samples.count == 22)  // 44 / 2 = 22
    }

    @Test("Non-integer ratio conversion")
    func nonIntegerRatioConversion() {
        // Arrange - 44100 to 16000 (ratio 2.75625)
        let converter = SampleRateConverter(from: 44100, to: 16000)

        let buffer = AudioBuffer(
            samples: [Float](repeating: 0.5, count: 441),
            sampleRate: 44100,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let result = converter.convert(buffer: buffer)

        // Assert
        #expect(result.sampleRate == 16000)
        // 441 / 2.75625 = ~160
        #expect(result.samples.count == 160)
    }
}

// MARK: - Test Suite: Performance Characteristics

@Suite("SampleRateConverter: Performance")
struct SampleRateConverterPerformanceTests {

    @Test("Conversion of 1 second audio completes quickly")
    func oneSecondConversionPerformance() {
        // Arrange
        let converter = SampleRateConverter(from: 48000, to: 16000)

        // 1 second at 48kHz
        let buffer = AudioBuffer(
            samples: [Float](repeating: 0.5, count: 48000),
            sampleRate: 48000,
            timestamp: Date(),
            source: .microphone
        )

        // Act
        let startTime = Date()
        let result = converter.convert(buffer: buffer)
        let duration = Date().timeIntervalSince(startTime)

        // Assert - should complete in under 100ms
        #expect(duration < 0.1,
                "Conversion took \(duration * 1000)ms, expected < 100ms")
        #expect(result.samples.count == 16000)
    }
}
