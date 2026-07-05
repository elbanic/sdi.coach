// IPCClient.swift
// Unix Domain Socket client for Python backend communication
//
// Tasks implemented:
// - 1.3.1: Unix socket client connection
// - 1.3.2: Async message send/receive
// - 1.3.3: Reconnection with exponential backoff
// - 1.3.4: Response timeout handling

import Foundation
import Network

// MARK: - IPCError

/// Errors that can occur during IPC communication
public enum IPCError: Error, LocalizedError, Equatable {
    case notConnected
    case connectionFailed(String)
    case timeout(TimeInterval)
    case encodingFailed
    case decodingFailed(String)
    case maxRetriesExceeded(Int)
    case serverDisconnected
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "IPC client is not connected to server"
        case .connectionFailed(let reason):
            return "IPC connection failed: \(reason)"
        case .timeout(let seconds):
            return "IPC operation timeout after \(seconds) seconds"
        case .encodingFailed:
            return "Failed to encode IPC message (encoding error)"
        case .decodingFailed(let reason):
            return "Failed to decode IPC message (decoding error): \(reason)"
        case .maxRetriesExceeded(let attempts):
            return "Max reconnection retries exceeded (\(attempts) attempts)"
        case .serverDisconnected:
            return "Server disconnected unexpectedly"
        case .cancelled:
            return "IPC operation was cancelled"
        }
    }
}

// MARK: - ConnectionState

/// Represents the current state of the IPC connection
public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

// MARK: - ReconnectionConfig

/// Configuration for automatic reconnection with exponential backoff
public struct ReconnectionConfig: Sendable {
    /// Initial delay before first reconnection attempt (default: 1 second)
    public let initialDelay: TimeInterval

    /// Maximum delay between reconnection attempts (default: 30 seconds)
    public let maxDelay: TimeInterval

    /// Multiplier for exponential backoff (default: 2.0)
    public let multiplier: Double

    /// Maximum number of reconnection attempts (default: 5)
    public let maxRetries: Int

    public init(
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 180.0,
        multiplier: Double = 2.0,
        maxRetries: Int = 5
    ) {
        // Clamp values to reasonable minimums
        self.initialDelay = max(0.1, initialDelay)
        self.maxDelay = max(self.initialDelay, maxDelay)
        self.multiplier = max(1.0, multiplier)
        self.maxRetries = max(0, maxRetries)
    }

    /// Calculate the delay for a given reconnection attempt using exponential backoff
    /// - Parameter attempt: The zero-based attempt number
    /// - Returns: The delay in seconds, capped at maxDelay
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponentialDelay = initialDelay * pow(multiplier, Double(attempt))
        return min(exponentialDelay, maxDelay)
    }
}

// MARK: - IPCClient Actor

/// Unix Domain Socket client for communicating with the Python backend.
/// Uses Swift Concurrency (async/await) for all operations.
///
/// Features:
/// - Task 1.3.1: Unix socket connection via Network framework (NWConnection)
/// - Task 1.3.2: Async message send/receive with newline-delimited JSON
/// - Task 1.3.3: Automatic reconnection with exponential backoff
/// - Task 1.3.4: Configurable response timeouts
public actor IPCClient {

    // MARK: - Properties

    /// Path to the Unix domain socket
    public nonisolated let socketPath: String

    /// Default timeout for sendAndWait operations
    public nonisolated let defaultTimeout: TimeInterval

    /// Configuration for reconnection behavior
    public nonisolated let reconnectionConfig: ReconnectionConfig

    /// Current connection state
    public private(set) var connectionState: ConnectionState = .disconnected

    /// Whether automatic reconnection is enabled
    public private(set) var isAutoReconnectEnabled: Bool = false

    /// The underlying Network framework connection
    private var connection: NWConnection?

    /// Queue for Network framework callbacks
    private let networkQueue = DispatchQueue(label: "com.sdicoach.ipc.network", qos: .userInitiated)

    /// Buffer for receiving partial messages
    private var receiveBuffer = Data()

    /// Pending message continuations waiting for responses
    private var pendingResponses: [String: CheckedContinuation<IPCMessage, Error>] = [:]

    /// Continuation for connection completion
    private var connectContinuation: CheckedContinuation<Void, Error>?

    /// Current reconnection attempt count
    private var reconnectAttempt = 0

    /// Message handler for unsolicited messages (transcription, follow-up, etc.)
    private var messageHandler: ((IPCMessage) -> Void)?

    // MARK: - Computed Properties

    /// Whether the client is currently connected
    public var isConnected: Bool {
        connectionState == .connected
    }

    // MARK: - Initialization

    /// Creates a new IPC client
    /// - Parameters:
    ///   - socketPath: Path to the Unix domain socket (default: /tmp/sdicoach.sock)
    ///   - defaultTimeout: Default timeout for sendAndWait operations (default: 30 seconds)
    ///   - reconnectionConfig: Configuration for automatic reconnection
    public init(
        socketPath: String = "/tmp/sdicoach.sock",
        defaultTimeout: TimeInterval = 180.0,
        reconnectionConfig: ReconnectionConfig = ReconnectionConfig()
    ) {
        self.socketPath = socketPath
        self.defaultTimeout = defaultTimeout
        self.reconnectionConfig = reconnectionConfig
    }

    // MARK: - Connection Management (Task 1.3.1)

    /// Connects to the Unix domain socket server
    /// - Throws: `IPCError.connectionFailed` if connection cannot be established
    public func connect() async throws {
        guard connectionState == .disconnected || connectionState == .reconnecting else {
            if connectionState == .connected {
                return // Already connected
            }
            throw IPCError.connectionFailed("Connection already in progress")
        }

        connectionState = .connecting

        // Create Unix domain socket endpoint
        let endpoint = NWEndpoint.unix(path: socketPath)

        // Create TCP-like parameters for Unix socket
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()

        // Create and configure the connection
        let newConnection = NWConnection(to: endpoint, using: parameters)
        self.connection = newConnection

        // Wait for connection to be ready
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation

            newConnection.stateUpdateHandler = { [weak self] state in
                Task { [weak self] in
                    await self?.handleConnectionStateChange(state)
                }
            }

            newConnection.start(queue: networkQueue)
        }

        // Start receiving messages
        startReceiving()
    }

    /// Handles NWConnection state changes
    private func handleConnectionStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connectionState = .connected
            reconnectAttempt = 0
            connectContinuation?.resume()
            connectContinuation = nil

        case .failed(let error):
            connectionState = .disconnected
            let ipcError = IPCError.connectionFailed(error.localizedDescription)
            connectContinuation?.resume(throwing: ipcError)
            connectContinuation = nil

            // Cancel all pending responses
            for (_, continuation) in pendingResponses {
                continuation.resume(throwing: IPCError.serverDisconnected)
            }
            pendingResponses.removeAll()

            // Trigger reconnection if enabled
            if isAutoReconnectEnabled {
                Task {
                    await attemptReconnect()
                }
            }

        case .cancelled:
            connectionState = .disconnected
            connectContinuation?.resume(throwing: IPCError.cancelled)
            connectContinuation = nil

        case .waiting(let error):
            // Connection is waiting (e.g., no network)
            // Keep trying if auto-reconnect is enabled
            if !isAutoReconnectEnabled {
                connectionState = .disconnected
                let ipcError = IPCError.connectionFailed("Waiting: \(error.localizedDescription)")
                connectContinuation?.resume(throwing: ipcError)
                connectContinuation = nil
            }

        default:
            break
        }
    }

    /// Disconnects from the server
    public func disconnect() async {
        isAutoReconnectEnabled = false
        connection?.cancel()
        connection = nil
        connectionState = .disconnected
        receiveBuffer.removeAll()

        // Cancel all pending responses
        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: IPCError.cancelled)
        }
        pendingResponses.removeAll()
    }

    // MARK: - Auto-Reconnection (Task 1.3.3)

    /// Enables or disables automatic reconnection
    public func setAutoReconnect(enabled: Bool) {
        isAutoReconnectEnabled = enabled
    }

    /// Sets a handler for unsolicited messages (transcription, follow-up, etc.)
    /// - Parameter handler: Closure called when a message arrives that isn't a response to a pending request
    public func setMessageHandler(_ handler: @escaping (IPCMessage) -> Void) {
        messageHandler = handler
    }

    /// Attempts to reconnect with exponential backoff
    private func attemptReconnect() async {
        guard isAutoReconnectEnabled else { return }
        guard reconnectAttempt < reconnectionConfig.maxRetries else {
            connectionState = .disconnected
            return
        }

        connectionState = .reconnecting
        let delay = reconnectionConfig.delay(forAttempt: reconnectAttempt)
        reconnectAttempt += 1

        // Wait before attempting reconnection
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        guard isAutoReconnectEnabled else { return }

        do {
            try await connect()
        } catch {
            // Connection failed, will retry via state handler if auto-reconnect still enabled
        }
    }

    // MARK: - Message Send/Receive (Task 1.3.2)

    /// Sends an IPC message to the server
    /// - Parameter message: The message to send
    /// - Throws: `IPCError.notConnected` if not connected, `IPCError.encodingFailed` if encoding fails
    public func send(_ message: IPCMessage) async throws {
        guard connectionState == .connected, let connection = connection else {
            throw IPCError.notConnected
        }

        // Encode message to JSON with newline delimiter
        let jsonData: Data
        do {
            jsonData = try message.toJSONData()
        } catch {
            throw IPCError.encodingFailed
        }

        // Append newline delimiter for message framing
        var dataToSend = jsonData
        dataToSend.append(contentsOf: [0x0A]) // newline character

        // Send data asynchronously
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: dataToSend, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: IPCError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Receives a single IPC message from the server
    /// - Returns: The received message
    /// - Throws: `IPCError.notConnected` if not connected, `IPCError.decodingFailed` if decoding fails
    public func receive() async throws -> IPCMessage {
        guard connectionState == .connected, let connection = connection else {
            throw IPCError.notConnected
        }

        // Check if we already have a complete message in the buffer
        if let message = extractMessageFromBuffer() {
            return message
        }

        // Receive more data
        return try await withCheckedThrowingContinuation { continuation in
            receiveData(from: connection) { [weak self] result in
                Task { [weak self] in
                    guard let self = self else {
                        continuation.resume(throwing: IPCError.serverDisconnected)
                        return
                    }

                    switch result {
                    case .success(let data):
                        await self.appendToBuffer(data)
                        if let message = await self.extractMessageFromBuffer() {
                            continuation.resume(returning: message)
                        } else {
                            // Need more data - recursively receive
                            // This is simplified; a production implementation would use a proper receive loop
                            continuation.resume(throwing: IPCError.decodingFailed("Incomplete message"))
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Appends data to the receive buffer
    private func appendToBuffer(_ data: Data) {
        receiveBuffer.append(data)
    }

    /// Extracts a complete message from the buffer if available
    private func extractMessageFromBuffer() -> IPCMessage? {
        // Look for newline delimiter
        guard let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) else {
            return nil
        }

        // Extract the message data (excluding newline)
        let messageData = receiveBuffer.prefix(upTo: newlineIndex)

        // Remove the message and newline from buffer
        receiveBuffer.removeSubrange(...newlineIndex)

        // Decode the message
        do {
            return try IPCMessage.fromJSONData(Data(messageData))
        } catch {
            return nil
        }
    }

    /// Receives raw data from the connection
    private func receiveData(from connection: NWConnection, completion: @escaping (Result<Data, IPCError>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
            if let error = error {
                completion(.failure(.connectionFailed(error.localizedDescription)))
                return
            }

            if isComplete && content == nil {
                completion(.failure(.serverDisconnected))
                return
            }

            if let data = content {
                completion(.success(data))
            } else {
                completion(.failure(.serverDisconnected))
            }
        }
    }

    /// Starts the continuous receive loop
    private func startReceiving() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { [weak self] in
                guard let self = self else { return }

                if let error = error {
                    await self.handleReceiveError(error)
                    return
                }

                if isComplete && content == nil {
                    await self.handleServerDisconnect()
                    return
                }

                if let data = content {
                    await self.processReceivedData(data)
                }

                // Continue receiving if still connected
                if await self.connectionState == .connected {
                    await self.startReceiving()
                }
            }
        }
    }

    /// Processes received data and dispatches complete messages
    private func processReceivedData(_ data: Data) async {
        receiveBuffer.append(data)

        // Extract and process all complete messages
        while let message = extractMessageFromBuffer() {
            // Check if this is a response to a pending request
            if let messageId = message.messageId, let continuation = pendingResponses.removeValue(forKey: messageId) {
                continuation.resume(returning: message)
            } else {
                // Unsolicited message - call handler if set
                messageHandler?(message)
            }
        }
    }

    /// Handles receive errors
    private func handleReceiveError(_ error: NWError) {
        connectionState = .disconnected

        // Cancel all pending responses
        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: IPCError.connectionFailed(error.localizedDescription))
        }
        pendingResponses.removeAll()

        if isAutoReconnectEnabled {
            Task {
                await attemptReconnect()
            }
        }
    }

    /// Handles server disconnect
    private func handleServerDisconnect() {
        connectionState = .disconnected

        // Cancel all pending responses
        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: IPCError.serverDisconnected)
        }
        pendingResponses.removeAll()

        if isAutoReconnectEnabled {
            Task {
                await attemptReconnect()
            }
        }
    }

    // MARK: - Send and Wait with Timeout (Task 1.3.4)

    /// Sends a message and waits for a response with timeout
    /// - Parameters:
    ///   - message: The message to send
    ///   - timeout: Timeout in seconds (default: uses defaultTimeout)
    /// - Returns: The response message
    /// - Throws: `IPCError.timeout` if no response within timeout, other errors for connection issues
    public func sendAndWait(_ message: IPCMessage, timeout: TimeInterval? = nil) async throws -> IPCMessage {
        guard connectionState == .connected else {
            throw IPCError.notConnected
        }

        let effectiveTimeout = timeout ?? defaultTimeout
        let messageId = message.messageId ?? UUID().uuidString

        // Create a message with an ID if it doesn't have one
        let messageToSend: IPCMessage
        if message.messageId == nil {
            messageToSend = IPCMessage(
                type: message.type,
                payload: message.payload,
                messageId: messageId,
                timestamp: message.timestamp
            )
        } else {
            messageToSend = message
        }

        // Send the message
        try await send(messageToSend)

        // Wait for response with timeout
        return try await withThrowingTaskGroup(of: IPCMessage.self) { group in
            // Add the response waiting task
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    Task {
                        await self.registerPendingResponse(messageId: messageId, continuation: continuation)
                    }
                }
            }

            // Add the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                throw IPCError.timeout(effectiveTimeout)
            }

            // Return the first result (response or timeout)
            guard let result = try await group.next() else {
                throw IPCError.timeout(effectiveTimeout)
            }

            // Cancel remaining tasks
            group.cancelAll()

            return result
        }
    }

    /// Registers a continuation for a pending response
    private func registerPendingResponse(messageId: String, continuation: CheckedContinuation<IPCMessage, Error>) {
        pendingResponses[messageId] = continuation
    }
}
