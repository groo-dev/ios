//
//  WebViewBridge.swift
//  Groo
//
//  Swift ↔ JavaScript message protocol for the Milkdown editor.
//  Defines the communication interface between native Swift and WebView.
//

import Foundation

// MARK: - Commands (Swift → JavaScript)

/// Commands that Swift sends to the JavaScript editor
enum EditorCommand {
    /// Set the markdown content in the editor
    case setContent(String)
    /// Set read-only mode
    case setReadOnly(Bool)
    /// Focus the editor
    case focus
    /// Blur the editor (remove focus)
    case blur

    /// Convert to JavaScript function call (safe - checks if editor exists)
    var jsCall: String {
        switch self {
        case .setContent(let content):
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            return "if(window.grooEditor){window.grooEditor.setContent(\"\(escaped)\")}"
        case .setReadOnly(let readOnly):
            return "if(window.grooEditor){window.grooEditor.setReadOnly(\(readOnly))}"
        case .focus:
            return "if(window.grooEditor){window.grooEditor.focus()}"
        case .blur:
            return "if(window.grooEditor){window.grooEditor.blur()}"
        }
    }
}

// MARK: - Events (JavaScript → Swift)

/// Events that JavaScript sends to Swift
enum EditorEvent {
    /// Editor has finished initializing
    case ready
    /// Content has changed (debounced)
    case contentChanged(String)
    /// JavaScript error occurred
    case error(String)

    /// Parse from JavaScript message
    static func parse(from message: [String: Any]) -> EditorEvent? {
        guard let type = message["type"] as? String else { return nil }

        switch type {
        case "ready":
            return .ready
        case "contentChanged":
            guard let content = message["content"] as? String else { return nil }
            return .contentChanged(content)
        case "error":
            let errorMessage = message["message"] as? String ?? "Unknown error"
            return .error(errorMessage)
        default:
            return nil
        }
    }
}

// MARK: - Bridge Handler Protocol

/// Protocol for handling editor events
protocol EditorBridgeDelegate: AnyObject {
    /// Called when the editor is ready
    func editorDidBecomeReady()
    /// Called when content changes
    func editorContentDidChange(_ content: String)
    /// Called when an error occurs
    func editorDidEncounterError(_ message: String)
}
