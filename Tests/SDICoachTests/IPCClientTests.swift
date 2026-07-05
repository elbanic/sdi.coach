// IPCClientTests.swift
// Tests for IPCClient - Unix Domain Socket client for Python backend communication
//
// Tasks covered:
// - 1.3.1: Unix socket client connection
// - 1.3.2: Async message send/receive
// - 1.3.3: Reconnection with exponential backoff
// - 1.3.4: Response timeout handling

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 1.3.1: Unix Socket Client Connection Tests

@Suite("IPCClient Connection Tests")
struct IPCClientConnectionTests {

    @Test("IPCClient initializes with default socket path")
    func testDefaultSocketPath() async throws {
        let client = IPCClient()
        #expect(client.socketPath == "/tmp/sdicoach.sock")
    }

    @Test("IPCClient initializes with custom socket path")
    func testCustomSocketPath() async throws {
        let customPath = "/tmp/test-socket.sock"
        let client = IPCClient(socketPath: customPath)
        #expect(client.socketPath == customPath)
    }

    @Test("IPCClient initial state is disconnected")
    func testInitialStateDisconnected() async throws {
        let client = IPCClient()
        let isConnected = await client.isConnected
        #expect(isConnected == false)
    }

    @Test("IPCClient connect throws when server not available")
    func testConnectFailsWithoutServer() async throws {
        let client = IPCClient(socketPath: "/tmp/nonexistent-\(UUID().uuidString).sock")

        await #expect(throws: IPCError.self) {
            try await client.connect()
        }
    }

    @Test("IPCClient disconnect is safe when not connected")
    func testDisconnectWhenNotConnected() async throws {
        let client = IPCClient()
        // Should not throw
        await client.disconnect()
        let isConnected = await client.isConnected
        #expect(isConnected == false)
    }
}

// MARK: - Task 1.3.2: Async Message Send/Receive Tests

@Suite("IPCClient Message Tests")
struct IPCClientMessageTests {

    @Test("IPCClient send throws when not connected")
    func testSendThrowsWhenDisconnected() async throws {
        let client = IPCClient()
        let message = IPCMessage.handshakeRequest()

        await #expect(throws: IPCError.notConnected) {
            try await client.send(message)
        }
    }

    @Test("IPCClient receive throws when not connected")
    func testReceiveThrowsWhenDisconnected() async throws {
        let client = IPCClient()

        await #expect(throws: IPCError.notConnected) {
            _ = try await client.receive()
        }
    }

    @Test("IPCClient sendAndWait throws when not connected")
    func testSendAndWaitThrowsWhenDisconnected() async throws {
        let client = IPCClient()
        let message = IPCMessage.handshakeRequest()

        await #expect(throws: IPCError.notConnected) {
            _ = try await client.sendAndWait(message)
        }
    }
}

// MARK: - Task 1.3.3: Reconnection with Exponential Backoff Tests

@Suite("IPCClient Reconnection Tests")
struct IPCClientReconnectionTests {

    @Test("IPCClient has default reconnection settings")
    func testDefaultReconnectionSettings() async throws {
        let client = IPCClient()
        let config = client.reconnectionConfig

        #expect(config.initialDelay == 1.0)
        #expect(config.maxDelay == 180.0)
        #expect(config.multiplier == 2.0)
        #expect(config.maxRetries == 5)
    }

    @Test("IPCClient accepts custom reconnection configuration")
    func testCustomReconnectionConfig() async throws {
        let customConfig = ReconnectionConfig(
            initialDelay: 0.5,
            maxDelay: 10.0,
            multiplier: 1.5,
            maxRetries: 3
        )
        let client = IPCClient(socketPath: "/tmp/test.sock", reconnectionConfig: customConfig)
        let config = client.reconnectionConfig

        #expect(config.initialDelay == 0.5)
        #expect(config.maxDelay == 10.0)
        #expect(config.multiplier == 1.5)
        #expect(config.maxRetries == 3)
    }

    @Test("ReconnectionConfig calculates correct exponential delays")
    func testExponentialBackoffCalculation() {
        let config = ReconnectionConfig(
            initialDelay: 1.0,
            maxDelay: 30.0,
            multiplier: 2.0,
            maxRetries: 10
        )

        // Verify exponential backoff sequence: 1, 2, 4, 8, 16, 30 (capped)
        #expect(config.delay(forAttempt: 0) == 1.0)
        #expect(config.delay(forAttempt: 1) == 2.0)
        #expect(config.delay(forAttempt: 2) == 4.0)
        #expect(config.delay(forAttempt: 3) == 8.0)
        #expect(config.delay(forAttempt: 4) == 16.0)
        #expect(config.delay(forAttempt: 5) == 30.0) // Capped at maxDelay
        #expect(config.delay(forAttempt: 6) == 30.0) // Still capped
    }

    @Test("IPCClient enableAutoReconnect toggles reconnection behavior")
    func testAutoReconnectToggle() async throws {
        let client = IPCClient()

        // Default should be disabled
        var isEnabled = await client.isAutoReconnectEnabled
        #expect(isEnabled == false)

        // Enable auto-reconnect
        await client.setAutoReconnect(enabled: true)
        isEnabled = await client.isAutoReconnectEnabled
        #expect(isEnabled == true)

        // Disable auto-reconnect
        await client.setAutoReconnect(enabled: false)
        isEnabled = await client.isAutoReconnectEnabled
        #expect(isEnabled == false)
    }
}

// MARK: - Task 1.3.4: Response Timeout Handling Tests

@Suite("IPCClient Timeout Tests")
struct IPCClientTimeoutTests {

    @Test("IPCClient has default timeout of 180 seconds")
    func testDefaultTimeout() async throws {
        let client = IPCClient()
        let timeout = client.defaultTimeout
        #expect(timeout == 180.0)
    }

    @Test("IPCClient accepts custom default timeout")
    func testCustomDefaultTimeout() async throws {
        let client = IPCClient(socketPath: "/tmp/test.sock", defaultTimeout: 60.0)
        let timeout = client.defaultTimeout
        #expect(timeout == 60.0)
    }

    @Test("sendAndWait respects custom timeout parameter")
    func testSendAndWaitCustomTimeout() async throws {
        // This test verifies the API accepts a timeout parameter
        // Actual timeout behavior tested with mock server in integration tests
        let client = IPCClient()
        let message = IPCMessage.handshakeRequest()

        // Should throw notConnected before timeout matters,
        // but verifies the API signature is correct
        await #expect(throws: IPCError.notConnected) {
            _ = try await client.sendAndWait(message, timeout: 5.0)
        }
    }
}

// MARK: - IPCError Tests

@Suite("IPCError Tests")
struct IPCErrorTests {

    @Test("IPCError.notConnected has correct description")
    func testNotConnectedDescription() {
        let error = IPCError.notConnected
        #expect(error.localizedDescription.contains("not connected"))
    }

    @Test("IPCError.connectionFailed has correct description")
    func testConnectionFailedDescription() {
        let error = IPCError.connectionFailed("Test reason")
        #expect(error.localizedDescription.contains("connection failed"))
    }

    @Test("IPCError.timeout has correct description")
    func testTimeoutDescription() {
        let error = IPCError.timeout(30.0)
        #expect(error.localizedDescription.contains("timeout"))
    }

    @Test("IPCError.encodingFailed has correct description")
    func testEncodingFailedDescription() {
        let error = IPCError.encodingFailed
        #expect(error.localizedDescription.contains("encoding"))
    }

    @Test("IPCError.decodingFailed has correct description")
    func testDecodingFailedDescription() {
        let error = IPCError.decodingFailed("Invalid JSON")
        #expect(error.localizedDescription.contains("decoding"))
    }

    @Test("IPCError.maxRetriesExceeded has correct description")
    func testMaxRetriesExceededDescription() {
        let error = IPCError.maxRetriesExceeded(5)
        #expect(error.localizedDescription.contains("retries"))
    }

    @Test("IPCError.serverDisconnected has correct description")
    func testServerDisconnectedDescription() {
        let error = IPCError.serverDisconnected
        #expect(error.localizedDescription.contains("disconnected"))
    }
}

// MARK: - ReconnectionConfig Tests

@Suite("ReconnectionConfig Tests")
struct ReconnectionConfigTests {

    @Test("ReconnectionConfig default initializer")
    func testDefaultInitializer() {
        let config = ReconnectionConfig()

        #expect(config.initialDelay == 1.0)
        #expect(config.maxDelay == 180.0)
        #expect(config.multiplier == 2.0)
        #expect(config.maxRetries == 5)
    }

    @Test("ReconnectionConfig clamps negative values")
    func testClampsNegativeValues() {
        let config = ReconnectionConfig(
            initialDelay: -1.0,
            maxDelay: -10.0,
            multiplier: -2.0,
            maxRetries: -5
        )

        // Should use minimum reasonable values
        #expect(config.initialDelay >= 0)
        #expect(config.maxDelay >= config.initialDelay)
        #expect(config.multiplier >= 1.0)
        #expect(config.maxRetries >= 0)
    }
}

// MARK: - Connection State Tests

@Suite("IPCClient Connection State Tests")
struct IPCClientConnectionStateTests {

    @Test("IPCClient reports correct connection state")
    func testConnectionStateReporting() async throws {
        let client = IPCClient()

        // Initially disconnected
        let state = await client.connectionState
        #expect(state == .disconnected)
    }

    @Test("ConnectionState enum has all required cases")
    func testConnectionStateEnumCases() {
        // Verify all states exist
        let states: [ConnectionState] = [
            .disconnected,
            .connecting,
            .connected,
            .reconnecting
        ]

        #expect(states.count == 4)
    }
}
