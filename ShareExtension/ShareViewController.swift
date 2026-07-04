//
//  ShareViewController.swift
//  ShareExtension
//
//  Handles sharing text, URLs, and files to Groo.
//  Saves to App Group for main app to process.
//

import UIKit
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "dev.groo.ios", category: "share")

class ShareViewController: UIViewController {

    private var appGroupId: String {
        #if DEBUG
        "group.dev.groo.ios.debug"
        #else
        "group.dev.groo.ios"
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // Process shared items
        handleSharedItems()
    }

    private func handleSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }

        Task {
            var sharedTexts: [String] = []
            var loadFailureCount = 0

            for item in extensionItems {
                guard let attachments = item.attachments else { continue }

                for attachment in attachments {
                    // Handle text
                    if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        do {
                            if let text = try await loadText(from: attachment) {
                                sharedTexts.append(text)
                            }
                        } catch {
                            loadFailureCount += 1
                            logger.error("Failed to load shared text: \(String(describing: error))")
                        }
                    }
                    // Handle URLs
                    else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        do {
                            if let url = try await loadURL(from: attachment) {
                                sharedTexts.append(url.absoluteString)
                            }
                        } catch {
                            loadFailureCount += 1
                            logger.error("Failed to load shared URL: \(String(describing: error))")
                        }
                    }
                }
            }

            // Save to App Group
            var saved = false
            if !sharedTexts.isEmpty {
                saved = saveToAppGroup(texts: sharedTexts)
            }

            await MainActor.run {
                if !sharedTexts.isEmpty && !saved {
                    cancel(reason: "Failed to save shared content")
                } else if sharedTexts.isEmpty && loadFailureCount > 0 {
                    cancel(reason: "Failed to load shared content")
                } else {
                    close()
                }
            }
        }
    }

    private func loadText(from attachment: NSItemProvider) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let text = data as? String {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadURL(from attachment: NSItemProvider) async throws -> URL? {
        return try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = data as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func saveToAppGroup(texts: [String]) -> Bool {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            logger.fault("App Group container unavailable (\(self.appGroupId)) — cannot save shared content")
            return false
        }

        let sharedItemsURL = containerURL.appendingPathComponent("shared_items.json")

        // Load existing items. A missing file is fine (start empty); an unreadable
        // file is moved aside so previously queued items stay recoverable on disk.
        var items: [SharedItem] = []
        if FileManager.default.fileExists(atPath: sharedItemsURL.path) {
            do {
                let data = try Data(contentsOf: sharedItemsURL)
                items = try JSONDecoder().decode([SharedItem].self, from: data)
            } catch {
                logger.error("Existing shared items file unreadable, moving aside: \(String(describing: error))")
                let corruptURL = containerURL.appendingPathComponent("shared_items.json.corrupt")
                do {
                    try? FileManager.default.removeItem(at: corruptURL)
                    try FileManager.default.moveItem(at: sharedItemsURL, to: corruptURL)
                } catch {
                    logger.error("Failed to move corrupt shared items file aside: \(String(describing: error))")
                }
            }
        }

        // Add new items
        for text in texts {
            items.append(SharedItem(
                id: UUID().uuidString,
                text: text,
                createdAt: Date()
            ))
        }

        // Save back
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: sharedItemsURL)
            return true
        } catch {
            logger.error("Failed to save shared items: \(String(describing: error))")
            return false
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancel(reason: String) {
        let error = NSError(
            domain: "dev.groo.ios.ShareExtension",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}

// MARK: - Shared Item Model

struct SharedItem: Codable {
    let id: String
    let text: String
    let createdAt: Date
}
