// SDICoach.swift
// Task 7.1.1 [Swift]: Application class (component assembly)
// Task 7.1.3: Global error handling and signal handling
//
// Main entry point for the sdi.coach CLI application.
// Coordinates all components: IPC, Audio, TUI, and Services.

import ArgumentParser
import Foundation

// MARK: - Application Configuration

/// Application configuration
struct AppConfig {
    let socketPath: String
    let debug: Bool
    let defaultQuestion: String?

    static let defaultSocketPath = "/tmp/sdicoach.sock"
    static let version = "0.1.0"
}

// MARK: - CLI Command

@main
struct SDICoach: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sdi.coach",
        abstract: "AI-powered System Design Interview Coach",
        discussion: """
            sdi.coach helps you practice system design interviews with
            real-time voice interaction and AI-powered feedback.

            Usage:
              1. Start the application
              2. Use /start "Design a URL shortener" to begin
              3. Speak your answers - AI will respond with follow-ups
              4. Use /end to finish and receive detailed feedback
            """,
        version: AppConfig.version
    )

    // MARK: - Arguments

    @Option(name: .shortAndLong, help: "Path to the backend Unix socket")
    var socket: String = AppConfig.defaultSocketPath

    @Option(name: .shortAndLong, help: "Start interview with this question")
    var question: String?

    @Flag(name: .shortAndLong, help: "Enable debug logging")
    var debug: Bool = false

    // MARK: - Run

    mutating func run() async throws {
        let config = AppConfig(
            socketPath: socket,
            debug: debug,
            defaultQuestion: question
        )

        let app = Application(config: config)
        await app.run()
    }
}

// MARK: - Application Class

/// Main application class that coordinates all components
/// Task 7.1.1: Component assembly with dependency injection
final class Application: @unchecked Sendable {

    // MARK: - Properties

    private let config: AppConfig

    /// IPC client for backend communication
    private var ipcClient: IPCClient?

    /// Microphone capture for audio input
    private var microphoneCapture: MicrophoneCapture?

    /// Sample rate converter (48kHz → 16kHz)
    private let sampleRateConverter = SampleRateConverter()

    /// TUI engine for user interface
    private var tuiEngine: TUIEngine?

    /// Interview service for session management
    private var interviewService: InterviewService?

    /// TTS engine for text-to-speech
    private var ttsEngine: TTSEngine?

    /// Running state
    private var isRunning = false

    /// Interview timer task
    private var timerTask: Task<Void, Never>?

    /// Buffer for accumulating user's answer from transcription
    private var answerBuffer: [String] = []

    /// Input handler for raw mode input with current input tracking
    private var inputHandler: InputHandler?

    /// Lock for thread safety
    private let lock = NSLock()

    // MARK: - Transcript Line Aggregation 
    /// Accumulated text on current transcript line
    private var lastTranscriptLine: String = ""

    /// Timestamp string for current line header
    private var lastTranscriptTimestamp: String = ""

    /// When the current line header was created
    private var lastHeaderTime: Date = Date.distantPast

    /// Seconds before starting a new transcript line
    private let headerInterval: TimeInterval = Constants.Transcript.headerIntervalSeconds

    /// Track if we have an active transcript line being updated
    private var hasActiveTranscriptLine = false

    /// Loading spinner task
    private var spinnerTask: Task<Void, Never>?

    /// Track if TTS is currently playing (for Enter to skip)
    private var isTTSPlaying = false

    // MARK: - Initialization

    init(config: AppConfig) {
        self.config = config
    }

    // MARK: - Main Entry Point

    /// Run the application
    func run() async {
        printBanner()

        // Setup signal handling (Task 7.1.3)
        setupSignalHandling()

        // Initialize components
        do {
            try await initialize()
        } catch {
            printError("Initialization failed: \(error.localizedDescription)")
            return
        }

        // Connect to backend
        do {
            try await connectToBackend()
        } catch {
            printError("Failed to connect to backend: \(error.localizedDescription)")
            printInfo("Make sure the backend server is running:")
            printInfo("  cd backend && python main.py")
            await cleanup()
            return
        }

        // Request microphone permission
        if await !requestMicrophonePermission() {
            printError("Microphone permission is required")
            await cleanup()
            return
        }

        // Run main loop
        isRunning = true
        await runMainLoop()

        // Cleanup
        await cleanup()
    }

    // MARK: - Initialization

    /// Initialize all components
    /// Task 7.1.1: Dependency injection pattern
    private func initialize() async throws {
        if config.debug {
            printDebug("Initializing components...")
        }

        // Create IPC client
        ipcClient = IPCClient(
            socketPath: config.socketPath,
            defaultTimeout: 180.0,
            reconnectionConfig: ReconnectionConfig(
                initialDelay: 1.0,
                maxDelay: 10.0,
                multiplier: 2.0,
                maxRetries: 3
            )
        )

        // Create microphone capture with delegate
        let mic = MicrophoneCapture(debug: config.debug)
        mic.delegate = self
        microphoneCapture = mic

        // Create TUI engine
        tuiEngine = TUIEngine()

        // Create input handler for raw mode input
        inputHandler = InputHandler()

        // Create TTS engine (requires IPC client adapter)
        if let client = ipcClient {
            let ttsIpcAdapter = TTSIPCClientAdapter(client: client)
            ttsEngine = TTSEngine(ipcClient: ttsIpcAdapter)
        }

        // Create interview service (requires IPC client and TTS)
        if let client = ipcClient {
            let interviewIpcAdapter = InterviewIPCClientAdapter(client: client)
            // TTS disabled until mlx-audio is installed
            interviewService = InterviewService(
                ipcClient: interviewIpcAdapter,
                ttsEngine: nil,
                feedbackTimeout: 300.0
            )
        }

        if config.debug {
            printDebug("Components initialized")
        }
    }

    /// Connect to the backend server
    private func connectToBackend() async throws {
        guard let client = ipcClient else {
            throw ApplicationError.notInitialized
        }

        printInfo("Connecting to backend...")

        try await client.connect()
        await client.setAutoReconnect(enabled: true)

        // Set up message handler for transcription, follow-ups, etc.
        await client.setMessageHandler { [weak self] message in
            Task { @MainActor in
                self?.handleIncomingMessage(message)
            }
        }

        printInfo("Connected to backend")
    }

    /// Request microphone permission
    private func requestMicrophonePermission() async -> Bool {
        guard let mic = microphoneCapture else {
            return false
        }

        if mic.checkPermission() {
            return true
        }

        printInfo("Requesting microphone permission...")
        let granted = await mic.requestPermission()

        if granted {
            printInfo("Microphone permission granted")
        }

        return granted
    }

    // MARK: - Main Loop

    /// Main event loop
    private func runMainLoop() async {
        guard tuiEngine != nil, let handler = inputHandler else {
            return
        }

        // Enable raw mode for input tracking
        do {
            try handler.enableRawMode()
        } catch {
            printError("Failed to enable raw mode: \(error.localizedDescription)")
            printInfo("Falling back to standard input mode")
        }

        // Ensure raw mode is disabled on exit
        defer {
            handler.disableRawMode()
        }

        printWelcome()

        // If question provided, start interview immediately
        if let question = config.defaultQuestion {
            await handleStartCommand(question: question)
        }

        // Read and process commands
        while isRunning {
            // Show prompt
            printPrompt()

            // Read input using raw mode handler (tracks currentInput)
            guard let input = handler.readInput() else {
                break
            }

            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // Check if TTS is playing - Enter press skips TTS
                if isTTSPlaying {
                    await handleTTSSkip()
                }
                continue
            }

            // Parse and handle command
            let command = CommandParser.parse(trimmed)
            await handleCommand(command)
        }
    }

    /// Handle a parsed command
    private func handleCommand(_ command: Command) async {
        switch command {
        case .start(let question):
            await handleStartCommand(question: question)

        case .answer:
            await handleAnswerCommand()

        case .pause:
            await handlePauseCommand()

        case .end:
            await handleEndCommand()

        case .quit:
            printInfo("Exiting...")
            isRunning = false

        case .unknown(let input):
            printError("Unknown command: \(input)")
            printHelp()
        }
    }

    /// Handle /start command
    private func handleStartCommand(question: String?) async {
        let sessionQuestion = question ?? "Design a URL shortener service"

        printCenteredBanner(sessionQuestion)
        tuiEngine?.startInterview(question: sessionQuestion)

        // Note: microphone capture will be started when TTS completes (tts_status: completed)
        // This prevents IPC message queue buildup during TTS

        // Start countdown timer (30 minutes)
        startTimer()

        // Show animated spinner while preparing
        startSpinner("Interviewer is preparing...")

        // Start interview in background (don't block main loop)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.interviewService?.startInterview(question: sessionQuestion)

                // Display the interviewer's opening question on main actor
                let transcript = self.interviewService?.transcriptManager.entries.last
                await MainActor.run {
                    self.stopSpinner()
                    if let transcript, transcript.source == .interviewer {
                        self.printInterviewerMessage(transcript.content, restorePrompt: true)
                    }
                    // Update status: waiting for user
                    self.tuiEngine?.setStatus("Listening... speak your answer, then type /answer to submit", type: .waiting)
                }
            } catch {
                let errorMessage = error.localizedDescription
                await MainActor.run {
                    self.stopSpinner()
                    self.printError("Interview start failed: \(errorMessage)")
                    self.tuiEngine?.clearStatus()
                }
            }
        }
    }

    /// Start the interview countdown timer
    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Constants.Timing.timerTickNanoseconds)
                guard let self = self, let engine = self.tuiEngine else { break }

                let remaining = engine.remainingSeconds - 1
                if remaining <= 0 {
                    engine.updateRemainingTime(0)
                    await MainActor.run {
                        self.printInfo("⏰ Time's up!")
                    }
                    // Send interview_time_up to backend for natural wrap-up
                    await self.sendInterviewTimeUp()
                    break
                }
                engine.updateRemainingTime(remaining)
            }
        }
    }

    /// Send interview_time_up message to backend when timer ends
    private func sendInterviewTimeUp() async {
        let message = IPCMessage.interviewTimeUp()
        do {
            guard let client = ipcClient else {
                if config.debug {
                    printDebug("IPC client not available for time up signal")
                }
                return
            }
            try await client.send(message)
            if config.debug {
                printDebug("interview_time_up message sent to backend")
            }
        } catch {
            if config.debug {
                printDebug("Failed to send interview_time_up: \(error.localizedDescription)")
            }
        }
        // Prompt user to end the interview
        await MainActor.run {
            self.printInfo("Type /end to receive your feedback")
        }
    }

    /// Stop the interview timer
    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Extract and clear the answer buffer (thread-safe)
    private func extractAnswerBuffer() -> String {
        lock.withLock {
            let answer = answerBuffer.joined(separator: " ")
            answerBuffer.removeAll()
            lastTranscriptLine = ""
            lastHeaderTime = Date.distantPast
            return answer
        }
    }

    /// Handle /answer command - submit accumulated answer to interviewer
    private func handleAnswerCommand() async {
        let answer = extractAnswerBuffer()

        if answer.isEmpty {
            printError("No answer to submit. Speak your answer first, then use /answer")
            tuiEngine?.setStatus("Listening... speak your answer, then type /answer to submit", type: .waiting)
            return
        }

        // Stop microphone immediately - will resume when TTS completes
        microphoneCapture?.stopCapture()
        tuiEngine?.setMicrophoneOn(false)

        tuiEngine?.setStatus("LLM is thinking about your answer...", type: .thinking)

        do {
            // Send user response to backend
            try await interviewService?.sendUserResponse(answer)
            // Show animated spinner while waiting for response
            startSpinner("Interviewer is preparing...")
        } catch {
            printError("Failed to submit answer: \(error.localizedDescription)")
            tuiEngine?.setStatus("Error occurred. Try /answer again.", type: .error)
            // Resume microphone on error
            do {
                try microphoneCapture?.startCapture()
                tuiEngine?.setMicrophoneOn(true)
            } catch {
                printError("Failed to resume microphone: \(error.localizedDescription)")
            }
        }
    }

    /// Handle /pause command
    private func handlePauseCommand() async {
        printInfo("Interview paused")
        stopTimer()
        microphoneCapture?.stopCapture()
        tuiEngine?.setMicrophoneOn(false)
        await interviewService?.pauseInterview()
        tuiEngine?.setMode(.paused)
    }

    /// Handle TTS skip when Enter is pressed during TTS playback
    private func handleTTSSkip() async {
        printInfo("Skipping TTS...")

        // Send tts_stop to backend
        let message = IPCMessage.ttsStop()
        do {
            guard let client = ipcClient else {
                printError("IPC client not available")
                return
            }
            try await client.send(message)
            if config.debug {
                printDebug("tts_stop message sent to backend")
            }
        } catch {
            printError("Failed to send tts_stop: \(error.localizedDescription)")
            return
        }

        // Mark TTS as not playing
        // Microphone will be started when tts_status: stopped is received from backend
        isTTSPlaying = false
    }

    /// Handle incoming IPC messages (transcription, follow-ups, etc.)
    @MainActor
    private func handleIncomingMessage(_ message: IPCMessage) {
        switch message.type {
        case .transcription:
            // Display transcribed user speech (client-side aggregation client-side aggregation)
            if let text = message.payload["text"]?.value as? String, !text.isEmpty {
                let now = Date()
                let timeSinceLastHeader = now.timeIntervalSince(lastHeaderTime)

                // Should we start a new line? (if >7 seconds since last header)
                let shouldShowHeader = timeSinceLastHeader >= headerInterval

                lock.lock()
                // Add to answer buffer for /answer command
                answerBuffer.append(text)

                if shouldShowHeader {
                    // Start new transcript line
                    lastTranscriptLine = text
                    lastTranscriptTimestamp = tuiEngine?.formattedRemainingTime ?? "30:00"
                    lastHeaderTime = now
                    hasActiveTranscriptLine = true
                    lock.unlock()

                    printTranscriptNewLine(text, timestamp: lastTranscriptTimestamp)
                } else {
                    // Append to existing line
                    lastTranscriptLine += " " + text
                    lock.unlock()

                    printTranscriptUpdateLine(lastTranscriptLine, timestamp: lastTranscriptTimestamp)
                }
            }

        case .interviewQuestion:
            // Display interview question from interviewer (async, restore prompt)
            // This handles pipelined TTS transcript updates (sentences 2, 3, etc.)
            if let question = message.payload["question"]?.value as? String {
                tuiEngine?.setStatus("Listening... speak your answer, then type /answer to submit", type: .waiting)
                printInterviewerMessage(question, restorePrompt: true)
            }

        case .interviewFollowup:
            // Display follow-up question from interviewer (async, restore prompt)
            if let question = message.payload["question"]?.value as? String {
                stopSpinner()
                // Set status first, then print (so it can be displayed)
                tuiEngine?.setStatus("Listening... speak your answer, then type /answer to submit", type: .waiting)
                printInterviewerMessage(question, restorePrompt: true)
            }

        case .ttsStatus:
            // TTS status updates
            if let status = message.payload["status"]?.value as? String {
                if config.debug {
                    printDebug("TTS: \(status)")
                }
                switch status {
                case "speaking":
                    // Ensure microphone is off during TTS (defensive check)
                    isTTSPlaying = true
                    microphoneCapture?.stopCapture()
                    tuiEngine?.setMicrophoneOn(false)
                case "completed":
                    // TTS done, resume microphone capture
                    isTTSPlaying = false
                    do {
                        try microphoneCapture?.startCapture()
                        tuiEngine?.setMicrophoneOn(true)
                    } catch {
                        printError("Failed to resume microphone: \(error.localizedDescription)")
                    }
                    printInfo("🎙️ Your turn! Speak your answer, then type /answer to submit")
                    printPrompt()
                case "stopped":
                    // TTS was interrupted (e.g., user skipped)
                    isTTSPlaying = false
                    do {
                        try microphoneCapture?.startCapture()
                        tuiEngine?.setMicrophoneOn(true)
                    } catch {
                        printError("Failed to resume microphone: \(error.localizedDescription)")
                    }
                    printInfo("🎙️ Your turn! Speak your answer, then type /answer to submit")
                    printPrompt()
                default:
                    break
                }
            }

        case .error:
            // Handle backend error messages
            stopSpinner()
            if let errorType = message.payload["error"]?.value as? String,
               let errorMessage = message.payload["message"]?.value as? String {
                printError("Backend error [\(errorType)]: \(errorMessage)")
                tuiEngine?.setStatus("Error: \(errorMessage)", type: .error)
            }

        default:
            // Ignore other message types
            break
        }
    }

    /// Handle /end command
    private func handleEndCommand() async {
        printInfo("Ending interview...")
        stopTimer()
        microphoneCapture?.stopCapture()
        tuiEngine?.setMicrophoneOn(false)

        // Add any remaining answer buffer to transcript before ending
        let remainingAnswer = lock.withLock {
            let answer = answerBuffer.joined(separator: " ")
            answerBuffer.removeAll()
            return answer
        }

        if !remainingAnswer.isEmpty {
            interviewService?.transcriptManager.add(source: .user, content: remainingAnswer)
            printInfo("Added remaining answer to transcript")
        }

        do {
            // Save transcript first
            let transcriptPath = generateTranscriptPath()
            try interviewService?.transcriptManager.saveToFile(transcriptPath)

            // Request feedback
            tuiEngine?.setMode(.feedback)
            tuiEngine?.setStatus("Generating detailed feedback... this may take a moment", type: .thinking)

            if let feedback = try await interviewService?.requestFeedback() {
                // Save feedback to file
                let feedbackPath = generateFeedbackPath()
                try await interviewService?.saveFeedback(feedback, to: feedbackPath)
                tuiEngine?.setStatus("Files saved", type: .success)

                // Print summary with paths
                printFeedbackSummary(feedback, feedbackPath: feedbackPath, transcriptPath: transcriptPath)
            }

            try await interviewService?.endInterview()

        } catch {
            printError("Failed to end interview: \(error.localizedDescription)")
            tuiEngine?.setStatus("Error generating feedback", type: .error)
        }

        // Exit program after interview ends
        printInfo("Thank you for practicing! Goodbye.")
        isRunning = false
    }

    // MARK: - Signal Handling (Task 7.1.3)

    /// Setup signal handlers for graceful shutdown
    private func setupSignalHandling() {
        // Handle SIGINT (Ctrl+C)
        signal(SIGINT) { _ in
            print("\n")
            // Use a global flag since we can't capture self in signal handler
            SDICoachSignalHandler.shared.requestShutdown()
        }

        // Handle SIGTERM
        signal(SIGTERM) { _ in
            SDICoachSignalHandler.shared.requestShutdown()
        }

        // Monitor shutdown requests
        Task { [weak self] in
            for await _ in SDICoachSignalHandler.shared.shutdownStream {
                await self?.shutdown()
            }
        }
    }

    /// Graceful shutdown
    private func shutdown() async {
        if config.debug {
            printDebug("Initiating shutdown...")
        }

        isRunning = false

        // Stop microphone
        microphoneCapture?.stopCapture()

        // Disconnect from backend
        await ipcClient?.disconnect()

        printInfo("Shutdown complete")
        exit(0)
    }

    /// Cleanup resources
    private func cleanup() async {
        if config.debug {
            printDebug("Cleaning up resources...")
        }

        microphoneCapture?.stopCapture()
        await ipcClient?.disconnect()
    }

    // MARK: - Output Helpers

    private func printBanner() {
        print("""

        \u{001B}[36m╔═══════════════════════════════════════════════════════════════╗
        ║  ▐▛███▜▌ sdi.coach - System Design Interview Coach            ║
        ║   ▗▗ ▗▗  AI-powered mock interviews with real-time feedback   ║
        ║  ▐█████▌ Version \(AppConfig.version)                                        ║
        ╚═══════════════════════════════════════════════════════════════╝\u{001B}[0m
        """)
    }

    private func printWelcome() {
        print("""

        \u{001B}[33m📋 Interview Guide (Total: 30 minutes)\u{001B}[0m
        ─────────────────────────────────────────────────────────────────
        \u{001B}[90m🎧 Tip: Use earphones/headphones to prevent audio feedback
           and improve transcription accuracy.\u{001B}[0m
        ─────────────────────────────────────────────────────────────────
        1. Type \u{001B}[36m/start "Design a URL shortener"\u{001B}[0m to begin
        2. Please wait for the interviewer's response.
        3. Speak into your microphone (transcription will appear on screen)
        4. When finished speaking, type \u{001B}[36m/answer\u{001B}[0m (or \u{001B}[36m/a\u{001B}[0m) to submit
        5. The interviewer will respond with follow-up questions
        6. Repeat steps 2-4 until complete
        7. Type \u{001B}[36m/end\u{001B}[0m to finish and receive detailed feedback

        \u{001B}[32mCommands:\u{001B}[0m
          /start [question]  - Start interview (30 min timer begins)
          /answer (or /a)    - Submit your spoken answer
          /pause             - Pause the interview
          /end               - End interview, get feedback, and exit
          /quit              - Exit without feedback

        """)
    }

    /// Print simple prompt
    private func printPrompt() {
        print("\u{001B}[36m❯\u{001B}[0m ", terminator: "")
        fflush(stdout)
    }

    /// Style status message based on type
    private func styleStatusMessage(_ message: String, type: StatusType) -> String {
        switch type {
        case .info:
            return "\u{001B}[90m\(message)\u{001B}[0m"          // Gray
        case .waiting:
            return "\u{001B}[33m⏳ \(message)\u{001B}[0m"       // Yellow
        case .thinking:
            return "\u{001B}[36m✦ \(message)\u{001B}[0m"        // Cyan
        case .success:
            return "\u{001B}[32m✓ \(message)\u{001B}[0m"        // Green
        case .error:
            return "\u{001B}[31m✗ \(message)\u{001B}[0m"        // Red
        }
    }

    private func printHelp() {
        print("""
        \u{001B}[33mAvailable commands:\u{001B}[0m
          /start [question]  - Start interview
          /answer (or /a)    - Submit answer
          /pause             - Pause interview
          /end               - End and get feedback
          /quit              - Exit
        """)
    }

    private func printInfo(_ message: String) {
        print("\u{001B}[34mℹ\u{001B}[0m \(message)")
    }

    private func printCenteredBanner(_ message: String) {
        // ANSI colors
        let reset = "\u{001B}[0m"
        let cyan = "\u{001B}[36m"
        let yellow = "\u{001B}[33m"
        let magenta = "\u{001B}[35m"
        let white = "\u{001B}[97m"
        let dim = "\u{001B}[90m"

        let boxWidth = 52
        let topBorder = dim + "┌" + String(repeating: "─", count: boxWidth) + "┐" + reset
        let bottomBorder = dim + "└" + String(repeating: "─", count: boxWidth) + "┘" + reset

        // Title: "  🎤 Interview Started" = 2 + 2(emoji) + 1 + 9 + 1 + 7 = 22 visible chars
        let titleLine = "  \(cyan)🎤\(reset) \(magenta)Interview\(reset) \(yellow)Started\(reset)"
        let titleVisibleLen = 22
        let titlePadding = boxWidth - titleVisibleLen
        let titleRow = dim + "│" + reset + titleLine + String(repeating: " ", count: titlePadding) + dim + "│" + reset

        // Topic line: "  " + message
        let topicVisibleLen = 2 + message.count
        let topicPadding = max(0, boxWidth - topicVisibleLen)
        let topicRow = dim + "│" + reset + "  " + white + message + reset + String(repeating: " ", count: topicPadding) + dim + "│" + reset

        print("")
        print(topBorder)
        print(titleRow)
        print(topicRow)
        print(bottomBorder)
        print("")
    }

    private func printError(_ message: String) {
        print("\u{001B}[31m✗\u{001B}[0m \(message)")
    }

    private func printDebug(_ message: String) {
        if config.debug {
            print("\u{001B}[90m[DEBUG] \(message)\u{001B}[0m")
        }
    }

    // MARK: - Loading Spinner

    /// Start animated loading spinner
    private func startSpinner(_ message: String) {
        stopSpinner()
        spinnerTask = Task { @MainActor in
            let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
            var frameIndex = 0

            while !Task.isCancelled {
                let frame = frames[frameIndex % frames.count]
                // Clear line and print spinner
                print("\r\u{001B}[K\u{001B}[36m\(frame)\u{001B}[0m \(message)", terminator: "")
                fflush(stdout)

                frameIndex += 1
                try? await Task.sleep(nanoseconds: Constants.Timing.spinnerFrameNanoseconds)
            }
        }
    }

    /// Stop the loading spinner and clear the line
    private func stopSpinner() {
        spinnerTask?.cancel()
        spinnerTask = nil
        // Clear the spinner line
        print("\r\u{001B}[K", terminator: "")
        fflush(stdout)
    }

    private func printInterviewerMessage(_ message: String, restorePrompt: Bool = false) {
        let remainingTime = tuiEngine?.formattedRemainingTime ?? "30:00"
        // Don't wrap emoji in color codes
        let formattedMessage = "🧑‍💼 \u{001B}[33m[\(remainingTime)]\u{001B}[0m \(message)"

        if restorePrompt {
            // Async message: clear current line, print message, restore prompt with current input
            print("\r\u{001B}[K", terminator: "")          // Clear current line
            print(formattedMessage)                        // Print message (with newline)
            // Restore prompt with current user input
            if let handler = inputHandler {
                print("\u{001B}[36m❯\u{001B}[0m \(handler.getPromptWithCursor())", terminator: "")
            } else {
                print("\u{001B}[36m❯\u{001B}[0m ", terminator: "")
            }
            fflush(stdout)
        } else {
            // Sync message (from command handler): just print normally
            print("\n" + formattedMessage)
        }

        // Reset transcript tracking for new interviewer turn
        lock.lock()
        lastTranscriptLine = ""
        lastHeaderTime = Date.distantPast
        hasActiveTranscriptLine = false
        currentTranscriptLines = 0
        lock.unlock()
    }

    // MARK: - Transcript Display 
    /// Track number of lines used by current transcript (for cursor positioning)
    private var currentTranscriptLines: Int = 0

    /// Get terminal width
    private func getTerminalWidth() -> Int {
        var winsize = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &winsize) == 0 && winsize.ws_col > 0 {
            return Int(winsize.ws_col)
        }
        return 120
    }

    /// Print a new transcript line (first chunk of a new aggregation)
    private func printTranscriptNewLine(_ text: String, timestamp: String) {
        // Simple format: emoji, timestamp, text (no truncation - show full text)
        let line = "🎙️ \u{001B}[36m[\(timestamp)]\u{001B}[0m \(text)"

        // Pattern: clear current line, print transcript, restore prompt with input
        print("\r\u{001B}[K", terminator: "")              // Clear current line
        print(line)                                        // Print transcript (with newline)
        // Restore prompt with current user input
        if let handler = inputHandler {
            print("\u{001B}[36m❯\u{001B}[0m \(handler.getPromptWithCursor())", terminator: "")
        } else {
            print("\u{001B}[36m❯\u{001B}[0m ", terminator: "")
        }
        fflush(stdout)

        currentTranscriptLines = 1
    }

    /// Update existing transcript line (append more text)
    private func printTranscriptUpdateLine(_ accumulatedText: String, timestamp: String) {
        // Simple format: emoji, timestamp, text (no truncation - show full text)
        let line = "🎙️ \u{001B}[36m[\(timestamp)]\u{001B}[0m \(accumulatedText)"

        // Pattern: move up, clear, print transcript, restore prompt with input
        print("\r\u{001B}[K", terminator: "")              // Clear current line (prompt)
        print("\u{001B}[A\u{001B}[K", terminator: "")      // Move up and clear transcript line
        print(line)                                        // Print updated transcript (with newline)
        // Restore prompt with current user input
        if let handler = inputHandler {
            print("\u{001B}[36m❯\u{001B}[0m \(handler.getPromptWithCursor())", terminator: "")
        } else {
            print("\u{001B}[36m❯\u{001B}[0m ", terminator: "")
        }
        fflush(stdout)
    }

    private func printFeedbackSummary(_ feedback: String, feedbackPath: String, transcriptPath: String) {
        // Extract score if present
        if let scoreRange = feedback.range(of: "Score.*?([0-9]+)/10", options: .regularExpression) {
            let scoreLine = feedback[scoreRange]
            print("\n\u{001B}[32m📊 \(scoreLine)\u{001B}[0m")
        }

        print("\n\u{001B}[33mSaved files:\u{001B}[0m")
        print("  📝 Transcript: \(transcriptPath)")
        print("  📊 Feedback:   \(feedbackPath)")
        print("\u{001B}[90mReview the full report for detailed analysis.\u{001B}[0m")
    }

    private func generateFeedbackPath() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        return "sdi_feedback_\(timestamp).md"
    }

    private func generateTranscriptPath() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        return "sdi_transcript_\(timestamp).md"
    }
}

// MARK: - Application Errors

enum ApplicationError: Error, LocalizedError {
    case notInitialized
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Application not initialized"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        }
    }
}

// MARK: - Signal Handler

/// Global signal handler for shutdown requests
final class SDICoachSignalHandler: @unchecked Sendable {
    static let shared = SDICoachSignalHandler()

    private var shutdownContinuation: AsyncStream<Void>.Continuation?
    private(set) lazy var shutdownStream: AsyncStream<Void> = {
        AsyncStream { continuation in
            self.shutdownContinuation = continuation
        }
    }()

    private init() {}

    func requestShutdown() {
        shutdownContinuation?.yield(())
    }
}

// MARK: - Protocol Adapters

/// Adapter to make IPCClient conform to TTSIPCClientProtocol
private final class TTSIPCClientAdapter: TTSIPCClientProtocol, @unchecked Sendable {
    private let client: IPCClient

    init(client: IPCClient) {
        self.client = client
    }

    func send(_ message: IPCMessage) async throws {
        try await client.send(message)
    }

    func isConnected() async -> Bool {
        await client.isConnected
    }
}

/// Adapter to make IPCClient conform to IPCClientProtocol for InterviewService
private final class InterviewIPCClientAdapter: IPCClientProtocol, @unchecked Sendable {
    private let client: IPCClient

    init(client: IPCClient) {
        self.client = client
    }

    func send(_ message: IPCMessage) async throws {
        try await client.send(message)
    }

    func isConnected() async -> Bool {
        await client.isConnected
    }

    func sendAndWait(_ message: IPCMessage, timeout: TimeInterval) async throws -> IPCMessage {
        try await client.sendAndWait(message, timeout: timeout)
    }
}

// MARK: - AudioCaptureDelegate

extension Application: AudioCaptureDelegate {
    /// Called when audio data is captured from microphone
    func didCaptureAudio(buffer: AudioBuffer, source: AudioSource) {
        guard let client = ipcClient else { return }

        // Convert 48kHz → 16kHz for MLX-Whisper
        let convertedBuffer = sampleRateConverter.convert(buffer: buffer)

        // Convert Float32 samples to Int16 PCM bytes
        var pcmData = Data()
        for sample in convertedBuffer.samples {
            // Clamp to [-1, 1] and convert to Int16
            let clampedSample = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clampedSample * Constants.Audio.maxInt16Value)
            withUnsafeBytes(of: int16Value.littleEndian) { pcmData.append(contentsOf: $0) }
        }

        // Base64 encode
        let base64Audio = pcmData.base64EncodedString()

        // Create and send audio_data message
        let message = IPCMessage.audioData(
            audioBase64: base64Audio,
            sampleRate: convertedBuffer.sampleRate
        )

        // Send asynchronously (fire and forget)
        Task {
            do {
                try await client.send(message)
            } catch {
                if self.config.debug {
                    print("[DEBUG] Failed to send audio: \(error)")
                }
            }
        }
    }

    /// Called when an error occurs during capture
    func didEncounterError(error: AudioCaptureError) {
        printError("Microphone error: \(error.localizedDescription)")
    }
}
