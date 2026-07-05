// Command.swift
// Task 5.1.1: Command enum implementation
//
// Defines the Command enum for representing user commands in the CLI.
// Each command represents a user action that can be parsed from input.

import Foundation

/// Command enum for parsed user commands
///
/// Represents the different commands that users can input to control
/// the SDI Coach interview session.
public enum Command: Equatable, Sendable {
    /// Start an interview session, optionally with a specific question
    case start(question: String?)

    /// Submit the accumulated answer to the interviewer
    case answer

    /// Pause the current interview session
    case pause

    /// End the current interview session
    case end

    /// Quit the application entirely
    case quit

    /// Unknown or invalid command, preserves original input
    case unknown(input: String)
}
