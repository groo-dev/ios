//
//  ScratchpadWebView.swift
//  Groo
//
//  WKWebView wrapper for the Milkdown editor.
//  Handles Swift ↔ JavaScript communication via message handlers.
//

import SwiftUI
import WebKit

// MARK: - ScratchpadWebView

struct ScratchpadWebView: UIViewRepresentable {
    let initialContent: String
    let onContentChange: (String) -> Void
    let onReady: () -> Void
    let onError: (String) -> Void

    @Binding var webView: WKWebView?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Non-persistent data store (no caching)
        config.websiteDataStore = .nonPersistent()

        // Add message handler for JS → Swift communication
        config.userContentController.add(context.coordinator, name: "grooEditor")

        // Allow inline media playback
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = true
        webView.scrollView.isScrollEnabled = true
        webView.isOpaque = false
        webView.backgroundColor = .clear

        // Disable link preview
        webView.allowsLinkPreview = false

        // Load editor HTML
        // Try subdirectory first (folder reference), then root (group)
        let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Editor")
            ?? Bundle.main.url(forResource: "index", withExtension: "html")

        if let htmlURL = htmlURL {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            print("[ScratchpadWebView] ERROR: Could not find index.html in bundle")
        }

        // Store reference for external access
        DispatchQueue.main.async {
            self.webView = webView
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Content updates are handled via executeCommand
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ScratchpadWebView
        private var isReady = false
        private var pendingContent: String?

        init(_ parent: ScratchpadWebView) {
            self.parent = parent
            self.pendingContent = parent.initialContent
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "grooEditor",
                  let body = message.body as? [String: Any] else { return }

            if let event = EditorEvent.parse(from: body) {
                DispatchQueue.main.async { [weak self] in
                    self?.handleEvent(event)
                }
            }
        }

        private func handleEvent(_ event: EditorEvent) {
            switch event {
            case .ready:
                isReady = true
                // Set initial content if pending
                if let content = pendingContent {
                    executeCommand(.setContent(content))
                    pendingContent = nil
                }
                parent.onReady()

            case .contentChanged(let content):
                parent.onContentChange(content)

            case .error(let message):
                parent.onError(message)
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Page loaded, wait for editor ready event
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onError("Navigation failed: \(error.localizedDescription)")
        }

        // MARK: - Command Execution

        func executeCommand(_ command: EditorCommand) {
            guard let webView = parent.webView else { return }

            if !isReady, case .setContent(let content) = command {
                pendingContent = content
                return
            }

            webView.evaluateJavaScript(command.jsCall) { _, error in
                if let error = error {
                    self.parent.onError("JS error: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - WebView Command Extension

extension ScratchpadWebView {
    /// Execute a command on the editor
    func executeCommand(_ command: EditorCommand) {
        webView?.evaluateJavaScript(command.jsCall, completionHandler: nil)
    }
}
