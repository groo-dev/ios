//
//  WebViewBridgeTests.swift
//  GrooTests
//
//  Pure-logic tests for the JS bridge: EditorCommand JS generation
//  (escaping is the load-bearing part) and EditorEvent parsing.
//

import Testing
@testable import Groo

struct WebViewBridgeTests {
    @Test func setContentEscapesJSMetacharacters() {
        let js = EditorCommand.setContent(#"line "quoted" \ end"# + "\nnext\rline").jsCall
        #expect(js.contains(#"\\"#))          // backslash escaped
        #expect(js.contains(#"\""#))          // quote escaped
        #expect(js.contains(#"\n"#))          // newline escaped
        #expect(js.contains(#"\r"#))          // carriage return escaped
        #expect(!js.contains("\n"), "raw newline would break the JS string literal")
        #expect(js.contains("window.grooEditor"))
    }

    @Test func simpleCommandsProduceGuardedCalls() {
        #expect(EditorCommand.focus.jsCall.contains("window.grooEditor"))
        #expect(EditorCommand.blur.jsCall.contains("window.grooEditor"))
        #expect(EditorCommand.setReadOnly(true).jsCall.contains("true"))
        #expect(EditorCommand.setReadOnly(false).jsCall.contains("false"))
    }

    @Test func parseRecognizesAllEventTypes() throws {
        guard case .ready = try #require(EditorEvent.parse(from: ["type": "ready"])) else {
            Issue.record("expected .ready"); return
        }
        guard case .contentChanged(let content) =
                try #require(EditorEvent.parse(from: ["type": "contentChanged", "content": "# Hi"])) else {
            Issue.record("expected .contentChanged"); return
        }
        #expect(content == "# Hi")
        guard case .error(let message) =
                try #require(EditorEvent.parse(from: ["type": "error", "message": "boom"])) else {
            Issue.record("expected .error"); return
        }
        #expect(message == "boom")
    }

    @Test func parseRejectsUnknownAndMalformed() {
        #expect(EditorEvent.parse(from: ["type": "alien"]) == nil)
        #expect(EditorEvent.parse(from: [:]) == nil)
        #expect(EditorEvent.parse(from: ["type": "contentChanged"]) == nil)   // missing payload
    }
}
