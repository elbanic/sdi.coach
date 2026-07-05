// CommandParser.swift
// Task 5.1.2: CommandParser implementation
//
// Parses user input strings into Command enum values.
// Supports slash commands like /start, /pause, /end, /quit, /q

import Foundation

/// Command parser for parsing user input into commands
///
/// Supports the following command formats:
/// - `/start` - start with no question
/// - `/start "Design a URL shortener"` - start with quoted question
/// - `/start Design a URL shortener` - start with unquoted question
/// - `/answer` or `/a` - submit current answer to interviewer
/// - `/pause` - pause interview
/// - `/end` - end interview
/// - `/quit` or `/q` - quit application
/// - Any other input -> `unknown(input:)`
public struct CommandParser {

    public init() {}

    /// Parse a string input into a Command (instance method)
    ///
    /// - Parameter input: The user input string
    /// - Returns: Parsed Command
    public func parse(_ input: String) -> Command {
        Self.parse(input)
    }

    /// Parse a string input into a Command (static method)
    ///
    /// - Parameter input: The user input string
    /// - Returns: Parsed Command
    public static func parse(_ input: String) -> Command {
        // Trim leading/trailing whitespace for command detection
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if input starts with slash for command
        guard trimmed.hasPrefix("/") else {
            // Not a command, return as unknown with original input
            return .unknown(input: input)
        }

        // Split into command and arguments
        // Use whitespace to separate command from arguments
        let components = splitCommandAndArguments(trimmed)
        let commandName = components.command.lowercased()
        let arguments = components.arguments

        switch commandName {
        case "/start":
            return parseStartCommand(arguments: arguments)
        case "/answer", "/a":
            return .answer
        case "/pause":
            return .pause
        case "/end":
            return .end
        case "/quit", "/q":
            return .quit
        default:
            // Unknown command, return with original input
            return .unknown(input: input)
        }
    }

    // MARK: - Private Helpers

    /// Split input into command and arguments
    /// - Parameter input: The trimmed input string
    /// - Returns: Tuple with command name and remaining arguments
    private static func splitCommandAndArguments(_ input: String) -> (command: String, arguments: String?) {
        // Find first whitespace character
        guard let firstWhitespace = input.firstIndex(where: { $0.isWhitespace }) else {
            // No whitespace, entire input is command
            return (input, nil)
        }

        let command = String(input[..<firstWhitespace])
        let argumentsPart = String(input[firstWhitespace...]).trimmingCharacters(in: .whitespaces)

        // If arguments are empty after trimming, return nil
        if argumentsPart.isEmpty {
            return (command, nil)
        }

        return (command, argumentsPart)
    }

    /// Parse the start command with optional question argument
    /// - Parameter arguments: The arguments after /start command
    /// - Returns: Command.start with appropriate question value
    private static func parseStartCommand(arguments: String?) -> Command {
        guard let args = arguments, !args.isEmpty else {
            return .start(question: nil)
        }

        // Check for quoted string (double or single quotes)
        if let question = extractQuotedString(args) {
            // Empty quoted string "" or '' returns nil question
            if question.isEmpty {
                return .start(question: nil)
            }
            return .start(question: question)
        }

        // Unquoted argument - trim whitespace
        let trimmedQuestion = args.trimmingCharacters(in: .whitespaces)
        if trimmedQuestion.isEmpty {
            return .start(question: nil)
        }

        return .start(question: trimmedQuestion)
    }

    /// Extract string from quoted input
    /// Handles both double quotes and single quotes
    /// - Parameter input: The input string that may be quoted
    /// - Returns: The unquoted string content, or nil if not quoted
    private static func extractQuotedString(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Check for double quotes
        if trimmed.hasPrefix("\"") {
            return extractBetweenQuotes(trimmed, quote: "\"")
        }

        // Check for single quotes
        if trimmed.hasPrefix("'") {
            return extractBetweenQuotes(trimmed, quote: "'")
        }

        return nil
    }

    /// Extract content between matching quotes
    /// - Parameters:
    ///   - input: The input string starting with a quote
    ///   - quote: The quote character to match
    /// - Returns: The content between quotes
    private static func extractBetweenQuotes(_ input: String, quote: Character) -> String {
        let quoteString = String(quote)

        // Remove leading quote
        guard input.hasPrefix(quoteString) else {
            return input
        }

        var content = String(input.dropFirst())

        // Find closing quote
        if let closingQuoteIndex = content.lastIndex(of: quote) {
            // Check if it's actually at the end (after trimming)
            let afterQuote = String(content[content.index(after: closingQuoteIndex)...])
            if afterQuote.trimmingCharacters(in: .whitespaces).isEmpty {
                content = String(content[..<closingQuoteIndex])
            }
        }

        return content
    }
}
