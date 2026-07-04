//
//  ScratchpadEditorView.swift
//  Groo
//
//  WebView-based editor for a single scratchpad.
//

import SwiftUI
import WebKit
import os

struct ScratchpadEditorView: View {
    let scratchpad: DecryptedScratchpad
    let onContentChange: (String) -> Void

    @State private var webView: WKWebView?
    @State private var isReady = false

    var body: some View {
        ScratchpadWebView(
            initialContent: scratchpad.content,
            onContentChange: onContentChange,
            onReady: {
                isReady = true
                Log.scratchpad.info("Editor ready for pad: \(scratchpad.id)")
            },
            onError: { errorMessage in
                Log.scratchpad.error("Editor error: \(errorMessage)")
            },
            webView: $webView
        )
        .onChange(of: scratchpad.id) { oldId, newId in
            // When switching pads, update the content
            if oldId != newId, isReady {
                webView?.evaluateJavaScript(EditorCommand.setContent(scratchpad.content).jsCall) { _, error in
                    if let error = error {
                        Log.scratchpad.error("Failed to set editor content: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
