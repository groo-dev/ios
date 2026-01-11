//
//  ShareViewController.swift
//  ShareExtension
//
//  Handles sharing text, URLs, and files to Groo.
//  Saves to App Group for main app to process.
//

import UIKit
import UniformTypeIdentifiers

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

            for item in extensionItems {
                guard let attachments = item.attachments else { continue }

                for attachment in attachments {
                    // Handle text
                    if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        if let text = try? await loadText(from: attachment) {
                            sharedTexts.append(text)
                        }
                    }
                    // Handle URLs
                    else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        if let url = try? await loadURL(from: attachment) {
                            sharedTexts.append(url.absoluteString)
                        }
                    }
                }
            }

            // Save to App Group
            if !sharedTexts.isEmpty {
                saveToAppGroup(texts: sharedTexts)
            }

            await MainActor.run {
                close()
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

    private func saveToAppGroup(texts: [String]) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else { return }

        let sharedItemsURL = containerURL.appendingPathComponent("shared_items.json")

        // Load existing items
        var items: [SharedItem] = []
        if let data = try? Data(contentsOf: sharedItemsURL),
           let existing = try? JSONDecoder().decode([SharedItem].self, from: data) {
            items = existing
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
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: sharedItemsURL)
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

// MARK: - Shared Item Model

struct SharedItem: Codable {
    let id: String
    let text: String
    let createdAt: Date
}
