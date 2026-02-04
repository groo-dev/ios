//
//  ScratchpadEditorView.swift
//  Groo
//
//  WebView-based editor for a single scratchpad.
//

import SwiftUI
import WebKit

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
                print("[Editor] Ready for pad: \(scratchpad.id)")
            },
            onError: { errorMessage in
                print("[Editor] Error: \(errorMessage)")
            },
            webView: $webView
        )
        .onChange(of: scratchpad.id) { oldId, newId in
            // When switching pads, update the content
            if oldId != newId, isReady {
                webView?.evaluateJavaScript(EditorCommand.setContent(scratchpad.content).jsCall)
            }
        }
    }
}
