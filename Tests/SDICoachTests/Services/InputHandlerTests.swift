// InputHandlerTests.swift
// TDD RED Phase: Failing tests for InputHandler
//
// Tasks covered:
// - 5.2.3: Raw mode input handling
//
// Test framework: swift-testing (NOT XCTest)

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 5.2.3: Raw Mode Input Handling Tests

@Suite("InputHandler Raw Mode")
struct InputHandlerRawModeTests {

    @Test("InputHandler should be initializable")
    func testInputHandlerInit() {
        let handler = InputHandler()
        #expect(handler != nil)
    }

    @Test("InputHandler should support dependency injection for terminal IO")
    func testInputHandlerWithMockIO() {
        let mockIO = MockTerminalIO()
        let handler = InputHandler(terminalIO: mockIO)
        #expect(handler != nil)
    }

    @Test("enableRawMode should configure terminal for raw input")
    func testEnableRawMode() throws {
        let mockIO = MockTerminalIO()
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()

        #expect(mockIO.isRawModeEnabled)
    }

    @Test("disableRawMode should restore terminal to normal mode")
    func testDisableRawMode() throws {
        let mockIO = MockTerminalIO()
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        handler.disableRawMode()

        #expect(!mockIO.isRawModeEnabled)
    }

    @Test("enableRawMode should throw when terminal is not available")
    func testEnableRawModeThrowsWhenNoTerminal() {
        let mockIO = MockTerminalIO()
        mockIO.simulateNoTerminal = true
        let handler = InputHandler(terminalIO: mockIO)

        #expect(throws: InputError.noTerminal) {
            try handler.enableRawMode()
        }
    }

    @Test("isRawModeEnabled should return current raw mode state")
    func testIsRawModeEnabledProperty() throws {
        let mockIO = MockTerminalIO()
        let handler = InputHandler(terminalIO: mockIO)

        #expect(!handler.isRawModeEnabled)

        try handler.enableRawMode()
        #expect(handler.isRawModeEnabled)

        handler.disableRawMode()
        #expect(!handler.isRawModeEnabled)
    }

    @Test("enableRawMode should be idempotent")
    func testEnableRawModeIdempotent() throws {
        let mockIO = MockTerminalIO()
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        try handler.enableRawMode()  // Should not throw

        #expect(handler.isRawModeEnabled)
        #expect(mockIO.enableRawModeCallCount == 1)  // Only called once
    }

    @Test("disableRawMode should be safe to call when not in raw mode")
    func testDisableRawModeWhenNotEnabled() {
        let mockIO = MockTerminalIO()
        let handler = InputHandler(terminalIO: mockIO)

        // Should not throw or crash
        handler.disableRawMode()

        #expect(!handler.isRawModeEnabled)
    }
}

// MARK: - Character Reading Tests

@Suite("InputHandler Character Reading")
struct InputHandlerCharacterReadingTests {

    @Test("readChar should return character when available")
    func testReadCharReturnsCharacter() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "a"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let char = handler.readChar()

        #expect(char == "a")
    }

    @Test("readChar should return nil when no input available")
    func testReadCharReturnsNilWhenNoInput() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = ""
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let char = handler.readChar()

        #expect(char == nil)
    }

    @Test("readChar should handle Unicode characters")
    func testReadCharHandlesUnicode() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "가"  // Korean character
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let char = handler.readChar()

        #expect(char == "가")
    }

    @Test("readChar should handle emoji")
    func testReadCharHandlesEmoji() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "😀"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let char = handler.readChar()

        #expect(char == "😀")
    }

    @Test("readChar should return nil when not in raw mode")
    func testReadCharReturnsNilWhenNotRawMode() {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "a"
        let handler = InputHandler(terminalIO: mockIO)

        // Not in raw mode
        let char = handler.readChar()

        #expect(char == nil)
    }

    @Test("readKeyEvent should handle escape sequences for arrow keys")
    func testReadKeyEventHandlesArrowKeys() throws {
        let mockIO = MockTerminalIO()
        // Up arrow: ESC [ A
        mockIO.simulatedInput = "\u{1B}[A"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let keyEvent = handler.readKeyEvent()

        #expect(keyEvent == .arrowUp)
    }

    @Test("readKeyEvent should handle function keys")
    func testReadKeyEventHandlesFunctionKeys() throws {
        let mockIO = MockTerminalIO()
        // F1 key (common sequence)
        mockIO.simulatedInput = "\u{1B}OP"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let keyEvent = handler.readKeyEvent()

        #expect(keyEvent == .functionKey(1))
    }

    @Test("readKeyEvent should handle Ctrl+C")
    func testReadKeyEventHandlesCtrlC() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "\u{03}"  // Ctrl+C
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let keyEvent = handler.readKeyEvent()

        #expect(keyEvent == .controlC)
    }

    @Test("readKeyEvent should handle Enter key")
    func testReadKeyEventHandlesEnter() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "\r"  // Carriage return (Enter)
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let keyEvent = handler.readKeyEvent()

        #expect(keyEvent == .enter)
    }

    @Test("readKeyEvent should handle Backspace")
    func testReadKeyEventHandlesBackspace() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "\u{7F}"  // DEL (Backspace on macOS)
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let keyEvent = handler.readKeyEvent()

        #expect(keyEvent == .backspace)
    }

    @Test("readKeyEvent should handle Tab")
    func testReadKeyEventHandlesTab() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "\t"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let keyEvent = handler.readKeyEvent()

        #expect(keyEvent == .tab)
    }

    @Test("readKeyEvent should handle Escape key")
    func testReadKeyEventHandlesEscape() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "\u{1B}"  // ESC without following sequence
        mockIO.simulatedEscapeTimeout = true
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let keyEvent = handler.readKeyEvent()

        #expect(keyEvent == .escape)
    }
}

// MARK: - Line Reading Tests

@Suite("InputHandler Line Reading")
struct InputHandlerLineReadingTests {

    @Test("readLine should return line when Enter is pressed")
    func testReadLineReturnsLine() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "hello\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let line = handler.readLine()

        #expect(line == "hello")
    }

    @Test("readLine should return nil on Ctrl+D (EOF)")
    func testReadLineReturnsNilOnEOF() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "\u{04}"  // Ctrl+D (EOF)
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let line = handler.readLine()

        #expect(line == nil)
    }

    @Test("readLine should handle backspace for editing")
    func testReadLineHandlesBackspace() throws {
        let mockIO = MockTerminalIO()
        // Type "hello", backspace twice, then "p" + Enter = "help"
        mockIO.simulatedInput = "hello\u{7F}\u{7F}p\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let line = handler.readLine()

        #expect(line == "help")
    }

    @Test("readLine should return empty string when only Enter is pressed")
    func testReadLineReturnsEmptyOnEnterOnly() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let line = handler.readLine()

        #expect(line == "")
    }

    @Test("readLine should handle Unicode input")
    func testReadLineHandlesUnicode() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "한글 텍스트\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let line = handler.readLine()

        #expect(line == "한글 텍스트")
    }

    @Test("readLine should have prompt option")
    func testReadLineWithPrompt() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "user input\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let line = handler.readLine(prompt: "> ")

        #expect(line == "user input")
        // Prompt should have been written to output
        #expect(mockIO.writtenOutput.contains("> "))
    }

    @Test("readLine should have timeout option")
    func testReadLineWithTimeout() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = ""  // No input
        mockIO.simulateReadTimeout = true
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let line = handler.readLine(timeout: 0.1)

        #expect(line == nil)
    }

    @Test("readLine should not allow more than maxLength characters")
    func testReadLineMaxLength() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "this is a very long input\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let line = handler.readLine(maxLength: 10)

        #expect(line?.count ?? 0 <= 10)
    }
}

// MARK: - Command Input Tests

@Suite("InputHandler Command Input")
struct InputHandlerCommandInputTests {

    @Test("readCommand should parse slash commands")
    func testReadCommandParsesSlashCommands() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "/start\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let command = handler.readCommand()

        #expect(command == .start(question: nil))
    }

    @Test("readCommand should parse command with argument")
    func testReadCommandParsesArgument() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "/start \"Design a URL shortener\"\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let command = handler.readCommand()

        #expect(command == .start(question: "Design a URL shortener"))
    }

    @Test("readCommand should return unknown for invalid commands")
    func testReadCommandReturnsUnknown() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "/invalid\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let command = handler.readCommand()

        if case .unknown(let input) = command {
            #expect(input == "/invalid")
        } else {
            Issue.record("Expected unknown command")
        }
    }

    @Test("readCommand should handle /pause")
    func testReadCommandParsesPause() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "/pause\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let command = handler.readCommand()

        #expect(command == .pause)
    }

    @Test("readCommand should handle /end")
    func testReadCommandParsesEnd() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "/end\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let command = handler.readCommand()

        #expect(command == .end)
    }

    @Test("readCommand should handle /quit")
    func testReadCommandParsesQuit() throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "/quit\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let command = handler.readCommand()

        #expect(command == .quit)
    }
}

// MARK: - Input Error Handling Tests

@Suite("InputHandler Error Handling")
struct InputHandlerErrorHandlingTests {

    @Test("InputError should have noTerminal case")
    func testInputErrorNoTerminal() {
        let error = InputError.noTerminal
        #expect(error == .noTerminal)
    }

    @Test("InputError should have termcapFailed case")
    func testInputErrorTermcapFailed() {
        let error = InputError.termcapFailed
        #expect(error == .termcapFailed)
    }

    @Test("InputError should have readFailed case")
    func testInputErrorReadFailed() {
        let error = InputError.readFailed(errno: 5)
        if case .readFailed(let errnum) = error {
            #expect(errnum == 5)
        } else {
            Issue.record("Expected readFailed error")
        }
    }

    @Test("InputError should have description")
    func testInputErrorDescription() {
        let error = InputError.noTerminal
        #expect(!error.localizedDescription.isEmpty)
    }
}

// MARK: - Cleanup and Resource Management Tests

@Suite("InputHandler Resource Management")
struct InputHandlerResourceManagementTests {

    @Test("InputHandler should restore terminal on deinit")
    func testRestoreTerminalOnDeinit() throws {
        let mockIO = MockTerminalIO()

        do {
            let handler = InputHandler(terminalIO: mockIO)
            try handler.enableRawMode()
            #expect(mockIO.isRawModeEnabled)
            // handler goes out of scope here
        }

        // After deinit, terminal should be restored
        #expect(!mockIO.isRawModeEnabled)
    }

    @Test("InputHandler should handle SIGWINCH for terminal resize")
    func testHandlesSIGWINCH() throws {
        let mockIO = MockTerminalIO()
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()

        // Simulate SIGWINCH (window size change)
        mockIO.simulateSIGWINCH()

        // Handler should update terminal size
        #expect(handler.terminalSizeChanged)
    }

    @Test("InputHandler should save and restore original terminal settings")
    func testSaveRestoreTerminalSettings() throws {
        let mockIO = MockTerminalIO()
        mockIO.originalTerminalSettings = "original_settings"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        handler.disableRawMode()

        #expect(mockIO.currentTerminalSettings == "original_settings")
    }
}

// MARK: - Async Input Tests

@Suite("InputHandler Async Operations")
struct InputHandlerAsyncTests {

    @Test("readCharAsync should return character asynchronously")
    func testReadCharAsync() async throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "a"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let char = await handler.readCharAsync()

        #expect(char == "a")
    }

    @Test("readLineAsync should return line asynchronously")
    func testReadLineAsync() async throws {
        let mockIO = MockTerminalIO()
        mockIO.simulatedInput = "hello\r"
        let handler = InputHandler(terminalIO: mockIO)

        try handler.enableRawMode()
        let line = await handler.readLineAsync()

        #expect(line == "hello")
    }

}

// MARK: - Thread Safety Tests

@Suite("InputHandler Thread Safety")
struct InputHandlerThreadSafetyTests {

    @Test("InputHandler should be thread-safe for state queries")
    func testThreadSafeStateQueries() async throws {
        let mockIO = MockTerminalIO()
        let handler = InputHandler(terminalIO: mockIO)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = handler.isRawModeEnabled
                }
            }
        }

        // Should complete without crash
        #expect(true)
    }
}

// MARK: - Mock Types for Tests

/// Mock terminal IO for testing
final class MockTerminalIO: TerminalIOProviding, @unchecked Sendable {
    private let lock = NSLock()

    private var _isRawModeEnabled = false
    var isRawModeEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRawModeEnabled
    }

    var simulateNoTerminal = false
    var simulatedInput = ""
    var simulateReadTimeout = false
    var simulateNoInput = false
    var simulatedEscapeTimeout = false

    private var _writtenOutput = ""
    var writtenOutput: String {
        lock.lock()
        defer { lock.unlock() }
        return _writtenOutput
    }

    private var _enableRawModeCallCount = 0
    var enableRawModeCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _enableRawModeCallCount
    }

    var originalTerminalSettings: String = ""
    var currentTerminalSettings: String = ""

    private var _terminalSizeChanged = false
    var terminalSizeChanged: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _terminalSizeChanged
    }

    public func enableRawMode() throws {
        lock.lock()
        defer { lock.unlock() }

        if simulateNoTerminal {
            throw InputError.noTerminal
        }

        if !_isRawModeEnabled {
            _enableRawModeCallCount += 1
            _isRawModeEnabled = true
        }
    }

    public func disableRawMode() {
        lock.lock()
        defer { lock.unlock() }
        _isRawModeEnabled = false
        currentTerminalSettings = originalTerminalSettings
    }

    public func read() -> UInt8? {
        lock.lock()
        defer { lock.unlock() }

        if simulateNoInput || simulatedInput.isEmpty {
            return nil
        }

        if simulateReadTimeout {
            return nil
        }

        let char = simulatedInput.removeFirst()
        return char.asciiValue
    }

    public func readUTF8() -> Character? {
        lock.lock()
        defer { lock.unlock() }

        if simulateNoInput || simulatedInput.isEmpty {
            return nil
        }

        return simulatedInput.removeFirst()
    }

    public func write(_ string: String) {
        lock.lock()
        defer { lock.unlock() }
        _writtenOutput += string
    }

    func simulateSIGWINCH() {
        lock.lock()
        defer { lock.unlock() }
        _terminalSizeChanged = true
    }

    func hasEscapeTimeout() -> Bool {
        return simulatedEscapeTimeout
    }
}
