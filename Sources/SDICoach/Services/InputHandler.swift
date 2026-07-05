// InputHandler.swift
// Task 5.2.3: Raw mode input handling
//
// Implements:
// - Raw mode enable/disable via termios
// - Character and line reading with Unicode support
// - Special key handling (arrows, Ctrl+C, etc.)
// - Command parsing

import Foundation
#if os(macOS) || os(Linux)
import Darwin
#endif

// MARK: - Protocol for Terminal IO (Dependency Injection)

/// Protocol for terminal IO operations
/// Allows dependency injection for testing
public protocol TerminalIOProviding: Sendable {
    func enableRawMode() throws
    func disableRawMode()
    func read() -> UInt8?
    func readUTF8() -> Character?
    func write(_ string: String)
    func hasEscapeTimeout() -> Bool

    /// Whether terminal size has changed (for SIGWINCH handling)
    /// Default implementation returns false
    var terminalSizeChanged: Bool { get }
}

// Default implementation for terminalSizeChanged
public extension TerminalIOProviding {
    var terminalSizeChanged: Bool { false }
}

// MARK: - Default Terminal IO Provider

/// Default terminal IO provider using termios
public final class DefaultTerminalIO: TerminalIOProviding, @unchecked Sendable {
    private var originalTermios: termios?
    private let lock = NSLock()
    private var isRawMode = false

    public init() {}

    public func enableRawMode() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRawMode else { return }

        // Check if stdin is a terminal
        guard isatty(STDIN_FILENO) != 0 else {
            throw InputError.noTerminal
        }

        // Save original terminal settings
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw InputError.termcapFailed
        }
        originalTermios = original

        // Configure raw mode
        var raw = original
        // Disable echo and canonical mode (keep ISIG for Ctrl+C)
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON))
        // Disable input processing (but keep ICRNL for CR->LF conversion)
        raw.c_iflag &= ~(UInt(IXON))
        // Keep OPOST enabled for proper \n -> \r\n conversion in output

        // Set minimum characters for read
        raw.c_cc.4 = 0  // VMIN - return immediately with whatever is available
        raw.c_cc.5 = 1  // VTIME - wait up to 0.1 seconds

        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw InputError.termcapFailed
        }

        isRawMode = true
    }

    public func disableRawMode() {
        lock.lock()
        defer { lock.unlock() }

        guard isRawMode, var original = originalTermios else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        isRawMode = false
    }

    public func read() -> UInt8? {
        var byte: UInt8 = 0
        let result = Darwin.read(STDIN_FILENO, &byte, 1)
        return result == 1 ? byte : nil
    }

    public func readUTF8() -> Character? {
        // Read first byte
        guard let firstByte = read() else { return nil }

        // Determine UTF-8 sequence length
        let sequenceLength: Int
        if firstByte & 0x80 == 0 {
            // ASCII
            return Character(UnicodeScalar(firstByte))
        } else if firstByte & 0xE0 == 0xC0 {
            sequenceLength = 2
        } else if firstByte & 0xF0 == 0xE0 {
            sequenceLength = 3
        } else if firstByte & 0xF8 == 0xF0 {
            sequenceLength = 4
        } else {
            // Invalid UTF-8 start byte
            return Character(UnicodeScalar(firstByte))
        }

        // Read remaining bytes
        var bytes = [firstByte]
        for _ in 1..<sequenceLength {
            guard let byte = read() else { break }
            bytes.append(byte)
        }

        // Decode UTF-8
        if let str = String(bytes: bytes, encoding: .utf8), let char = str.first {
            return char
        }

        return Character(UnicodeScalar(firstByte))
    }

    public func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    public func hasEscapeTimeout() -> Bool {
        // Check if more input is available within timeout
        var fds = pollfd()
        fds.fd = STDIN_FILENO
        fds.events = Int16(POLLIN)

        // Wait 50ms for additional input
        let result = poll(&fds, 1, 50)
        return result <= 0  // Timeout if no input available
    }

    deinit {
        disableRawMode()
    }
}

// MARK: - Input Errors

/// Errors that can occur during input handling
public enum InputError: Error, Equatable, Sendable {
    case noTerminal
    case termcapFailed
    case readFailed(errno: Int32)

    public var localizedDescription: String {
        switch self {
        case .noTerminal:
            return "No terminal available"
        case .termcapFailed:
            return "Failed to read terminal capabilities"
        case .readFailed(let errno):
            return "Read failed with errno: \(errno)"
        }
    }
}

// MARK: - Key Events

/// Key events for special keys and key combinations
public enum KeyEvent: Equatable, Sendable {
    case character(Character)
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case enter
    case backspace
    case tab
    case escape
    case controlC
    case controlD
    case functionKey(Int)
    case home
    case end
    case pageUp
    case pageDown
    case delete
}

// MARK: - InputHandler

/// Input handler for raw mode terminal input
///
/// Task 5.2.3: Raw mode input handling
/// - Enable/disable raw mode for character-by-character input
/// - Read characters and handle special keys
/// - Read lines with editing support
public final class InputHandler: @unchecked Sendable {

    // MARK: - Properties

    private let terminalIO: TerminalIOProviding
    private let lock = NSLock()
    private var _isRawModeEnabled = false
    private var _terminalSizeChanged = false

    /// Current input buffer (for display restoration during async updates)
    public private(set) var currentInput: String = ""

    /// Cursor position within currentInput (0 = start, count = end)
    private var cursorPosition: Int = 0

    /// Whether raw mode is currently enabled
    public var isRawModeEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRawModeEnabled
    }

    /// Whether terminal size has changed (for SIGWINCH handling)
    public var terminalSizeChanged: Bool {
        lock.lock()
        defer { lock.unlock() }
        // Check both internal flag and terminal IO provider
        return _terminalSizeChanged || terminalIO.terminalSizeChanged
    }

    // MARK: - Initialization

    /// Default initializer
    public init() {
        self.terminalIO = DefaultTerminalIO()
    }

    /// Initializer with custom terminal IO provider (for testing)
    public init(terminalIO: TerminalIOProviding) {
        self.terminalIO = terminalIO

        // Check if mockIO has terminalSizeChanged property
        if let mockIO = terminalIO as? MockTerminalIOCheckable {
            observeTerminalSizeChange(mockIO)
        }
    }

    private func observeTerminalSizeChange(_ mockIO: MockTerminalIOCheckable) {
        // This is called when we need to sync with mock's state
    }

    deinit {
        // Restore terminal on deinitialization
        if _isRawModeEnabled {
            terminalIO.disableRawMode()
        }
    }

    // MARK: - Raw Mode Control

    /// Enable raw mode for character-by-character input
    ///
    /// In raw mode:
    /// - Input is not line-buffered
    /// - Echo is disabled
    /// - Special characters are not processed
    ///
    /// - Throws: `InputError.noTerminal` if not attached to a terminal
    /// - Throws: `InputError.termcapFailed` if terminal configuration fails
    public func enableRawMode() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !_isRawModeEnabled else { return }

        try terminalIO.enableRawMode()
        _isRawModeEnabled = true
    }

    /// Disable raw mode and restore normal terminal settings
    public func disableRawMode() {
        lock.lock()
        defer { lock.unlock() }

        guard _isRawModeEnabled else { return }

        terminalIO.disableRawMode()
        _isRawModeEnabled = false
    }

    // MARK: - Character Reading

    /// Read a single character (blocking)
    ///
    /// - Returns: The character read, or nil if no input available
    public func readChar() -> Character? {
        lock.lock()
        let enabled = _isRawModeEnabled
        lock.unlock()

        guard enabled else { return nil }

        return terminalIO.readUTF8()
    }

    /// Read a key event, handling escape sequences for special keys
    ///
    /// - Returns: The key event representing the key pressed
    public func readKeyEvent() -> KeyEvent? {
        lock.lock()
        let enabled = _isRawModeEnabled
        lock.unlock()

        guard enabled else { return nil }

        // Try to read a byte first
        guard let byte = terminalIO.read() else {
            // If read() returns nil, try readUTF8() for Unicode characters
            // This handles cases where the terminal IO provider doesn't support byte-level UTF-8
            if let char = terminalIO.readUTF8() {
                return .character(char)
            }
            return nil
        }

        // Control characters
        switch byte {
        case 0x03:  // Ctrl+C
            return .controlC
        case 0x04:  // Ctrl+D
            return .controlD
        case 0x09:  // Tab
            return .tab
        case 0x0D:  // Carriage return (Enter)
            return .enter
        case 0x7F:  // DEL (Backspace on macOS)
            return .backspace
        case 0x08:  // BS (Backspace)
            return .backspace
        case 0x1B:  // Escape
            return handleEscapeSequence()
        default:
            break
        }

        // Regular character - need to handle UTF-8
        if byte & 0x80 == 0 {
            // ASCII
            return .character(Character(UnicodeScalar(byte)))
        }

        // Multi-byte UTF-8
        let sequenceLength: Int
        if byte & 0xE0 == 0xC0 {
            sequenceLength = 2
        } else if byte & 0xF0 == 0xE0 {
            sequenceLength = 3
        } else if byte & 0xF8 == 0xF0 {
            sequenceLength = 4
        } else {
            return .character(Character(UnicodeScalar(byte)))
        }

        var bytes = [byte]
        for _ in 1..<sequenceLength {
            guard let nextByte = terminalIO.read() else { break }
            bytes.append(nextByte)
        }

        if let str = String(bytes: bytes, encoding: .utf8), let char = str.first {
            return .character(char)
        }

        return .character(Character(UnicodeScalar(byte)))
    }

    /// Handle escape sequences for special keys
    private func handleEscapeSequence() -> KeyEvent {
        // Check if there's more input coming (escape sequence) or just escape key
        if terminalIO.hasEscapeTimeout() {
            return .escape
        }

        guard let byte1 = terminalIO.read() else {
            return .escape
        }

        // CSI sequences (ESC [)
        if byte1 == 0x5B {  // '['
            guard let byte2 = terminalIO.read() else {
                return .escape
            }

            switch byte2 {
            case 0x41:  // A - Up
                return .arrowUp
            case 0x42:  // B - Down
                return .arrowDown
            case 0x43:  // C - Right
                return .arrowRight
            case 0x44:  // D - Left
                return .arrowLeft
            case 0x48:  // H - Home
                return .home
            case 0x46:  // F - End
                return .end
            case 0x31...0x36:  // Extended sequences
                _ = terminalIO.read()  // Read trailing '~'
                switch byte2 {
                case 0x31:  // Home
                    return .home
                case 0x32:  // Insert
                    return .escape
                case 0x33:  // Delete
                    return .delete
                case 0x34:  // End
                    return .end
                case 0x35:  // Page Up
                    return .pageUp
                case 0x36:  // Page Down
                    return .pageDown
                default:
                    return .escape
                }
            default:
                return .escape
            }
        }

        // SS3 sequences (ESC O) for function keys
        if byte1 == 0x4F {  // 'O'
            guard let byte2 = terminalIO.read() else {
                return .escape
            }

            switch byte2 {
            case 0x50:  // P - F1
                return .functionKey(1)
            case 0x51:  // Q - F2
                return .functionKey(2)
            case 0x52:  // R - F3
                return .functionKey(3)
            case 0x53:  // S - F4
                return .functionKey(4)
            default:
                return .escape
            }
        }

        return .escape
    }

    // MARK: - Line Reading

    /// Read a line of input with editing support
    ///
    /// Supports:
    /// - Backspace for editing
    /// - Enter to submit
    /// - Ctrl+D for EOF
    ///
    /// - Parameters:
    ///   - prompt: Optional prompt to display (default: nil)
    ///   - timeout: Optional timeout in seconds (default: nil, blocking)
    ///   - maxLength: Maximum length of input (default: Int.max)
    /// - Returns: The line entered, or nil on EOF/timeout
    public func readLine(
        prompt: String? = nil,
        timeout: TimeInterval? = nil,
        maxLength: Int = Int.max
    ) -> String? {
        lock.lock()
        let enabled = _isRawModeEnabled
        lock.unlock()

        guard enabled else { return nil }

        // Display prompt if provided
        if let prompt = prompt {
            terminalIO.write(prompt)
        }

        var buffer = ""
        let startTime = Date()

        while true {
            // Check timeout
            if let timeout = timeout {
                if Date().timeIntervalSince(startTime) >= timeout {
                    return nil
                }
            }

            // Use readChar for Unicode support, falling back to readKeyEvent for special keys
            if let char = terminalIO.readUTF8() {
                // Check for special control characters
                switch char {
                case "\r", "\n":  // Enter
                    terminalIO.write("\r\n")
                    return buffer

                case "\u{04}":  // Ctrl+D (EOF)
                    return nil

                case "\u{03}":  // Ctrl+C
                    return nil

                case "\u{7F}", "\u{08}":  // Backspace (DEL or BS)
                    if !buffer.isEmpty {
                        buffer.removeLast()
                        // Echo backspace
                        terminalIO.write("\u{08} \u{08}")
                    }

                case "\u{1B}":  // Escape - skip escape sequences for line reading
                    // Read and discard escape sequence
                    _ = terminalIO.readUTF8()  // Likely '[' or 'O'
                    _ = terminalIO.readUTF8()  // Sequence character

                default:
                    // Regular character
                    if buffer.count < maxLength {
                        buffer.append(char)
                        // Echo character
                        terminalIO.write(String(char))
                    }
                }
            } else {
                // No input available
                if timeout != nil {
                    // In timeout mode, continue waiting
                    usleep(10000)  // 10ms
                    continue
                }
                return nil
            }
        }
    }

    // MARK: - Prompt Restoration

    /// Get the prompt string with cursor position for async restoration
    /// Returns the input text and moves cursor back to correct position
    public func getPromptWithCursor() -> String {
        let moveBack = currentInput.count - cursorPosition
        if moveBack > 0 {
            return currentInput + "\u{001B}[\(moveBack)D"
        }
        return currentInput
    }

    /// Get current cursor position
    public func getCursorPosition() -> Int {
        return cursorPosition
    }

    /// Clear current input buffer
    public func clearCurrentInput() {
        currentInput = ""
        cursorPosition = 0
    }

    // MARK: - Raw Mode Input Reading

    /// Read input in raw mode with full editing support
    /// This method is designed for interactive input while async updates occur
    ///
    /// - Returns: The input string, or special control sequences for Ctrl+C/Ctrl+D
    public func readInput() -> String? {
        lock.lock()
        let enabled = _isRawModeEnabled
        lock.unlock()

        // If not in raw mode, fall back to standard readLine
        guard enabled else {
            return Swift.readLine()
        }

        currentInput = ""
        cursorPosition = 0

        while true {
            guard let byte = terminalIO.read() else {
                usleep(10000)  // 10ms
                continue
            }

            // Control characters
            switch byte {
            case 0x03:  // Ctrl+C
                return nil
            case 0x04:  // Ctrl+D
                return nil
            case 0x0A, 0x0D:  // Enter (LF or CR)
                print("")  // Move to next line
                let result = currentInput
                return result

            case 0x7F, 0x08:  // Backspace (DEL or BS)
                handleBackspaceInInput()
                continue

            case 0x1B:  // Escape sequence
                handleEscapeInInput()
                continue

            default:
                break
            }

            // UTF-8 multi-byte handling
            if byte > 127 {
                let sequenceLength: Int
                if byte & 0xE0 == 0xC0 {
                    sequenceLength = 2
                } else if byte & 0xF0 == 0xE0 {
                    sequenceLength = 3
                } else if byte & 0xF8 == 0xF0 {
                    sequenceLength = 4
                } else {
                    continue
                }

                var bytes = [byte]
                for _ in 1..<sequenceLength {
                    guard let nextByte = terminalIO.read() else { break }
                    bytes.append(nextByte)
                }

                if let str = String(bytes: bytes, encoding: .utf8) {
                    for char in str {
                        insertCharacter(char)
                    }
                }
                continue
            }

            // Regular printable character
            if byte >= 32 && byte < 127 {
                let char = Character(UnicodeScalar(byte))
                insertCharacter(char)
            }
        }
    }

    /// Insert a character at the current cursor position
    private func insertCharacter(_ char: Character) {
        let index = currentInput.index(currentInput.startIndex, offsetBy: cursorPosition)
        currentInput.insert(char, at: index)
        cursorPosition += 1

        // Redraw from cursor position
        let remaining = String(currentInput[index...])
        print(remaining, terminator: "")

        // Move cursor back to correct position
        let moveBack = remaining.count - 1
        if moveBack > 0 {
            print("\u{001B}[\(moveBack)D", terminator: "")
        }
        fflush(stdout)
    }

    /// Handle backspace in raw mode input
    private func handleBackspaceInInput() {
        guard cursorPosition > 0 else { return }

        let removeIndex = currentInput.index(currentInput.startIndex, offsetBy: cursorPosition - 1)
        currentInput.remove(at: removeIndex)
        cursorPosition -= 1

        // Move cursor left, redraw remaining text, clear extra char
        print("\u{001B}[1D", terminator: "")
        let remaining = String(currentInput[currentInput.index(currentInput.startIndex, offsetBy: cursorPosition)...])
        print(remaining + " ", terminator: "")

        // Move cursor back to correct position
        let moveBack = remaining.count + 1
        print("\u{001B}[\(moveBack)D", terminator: "")
        fflush(stdout)
    }

    /// Handle escape sequences in raw mode input
    private func handleEscapeInInput() {
        // Check for escape sequence
        if terminalIO.hasEscapeTimeout() {
            // Just escape key - ignore
            return
        }

        guard let byte1 = terminalIO.read() else { return }

        // CSI sequences (ESC [)
        if byte1 == 0x5B {
            guard let byte2 = terminalIO.read() else { return }

            switch byte2 {
            case 0x43:  // Right arrow
                if cursorPosition < currentInput.count {
                    cursorPosition += 1
                    print("\u{001B}[1C", terminator: "")
                    fflush(stdout)
                }
            case 0x44:  // Left arrow
                if cursorPosition > 0 {
                    cursorPosition -= 1
                    print("\u{001B}[1D", terminator: "")
                    fflush(stdout)
                }
            case 0x31...0x36:  // Extended sequences
                _ = terminalIO.read()  // Read trailing '~'
            default:
                break
            }
        }
    }

    // MARK: - Internal methods for testing

    /// Update terminal size changed flag (called by mock during tests)
    internal func setTerminalSizeChanged(_ changed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _terminalSizeChanged = changed
    }

    // MARK: - Command Reading

    /// Read input and parse as a Command
    /// Reads a line of input and parses it using CommandParser
    ///
    /// - Returns: The parsed Command
    public func readCommand() -> Command {
        guard let input = readInput() else {
            return .quit  // Ctrl+C or Ctrl+D
        }
        return CommandParser.parse(input)
    }

    // MARK: - Async Wrappers

    /// Read a single character asynchronously
    ///
    /// - Returns: The character read, or nil if interrupted
    public func readCharAsync() async -> Character? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [weak self] in
                let char = self?.readChar()
                continuation.resume(returning: char)
            }
        }
    }

    /// Read a line asynchronously
    ///
    /// - Parameter prompt: Optional prompt to display
    /// - Returns: The line read, or nil if interrupted
    public func readLineAsync(prompt: String? = nil) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [weak self] in
                if let p = prompt {
                    self?.terminalIO.write(p)
                }
                let line = self?.readInput()
                continuation.resume(returning: line)
            }
        }
    }
}

// MARK: - Protocol for Mock Testing

/// Protocol to check terminal size changes in mock
protocol MockTerminalIOCheckable {
    var terminalSizeChanged: Bool { get }
}
