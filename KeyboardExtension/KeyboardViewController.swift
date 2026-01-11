//
//  KeyboardViewController.swift
//  KeyboardExtension
//
//  Custom keyboard that shows recent Pad items for quick insertion.
//  Decrypts items using biometric-protected key from Keychain.
//

import UIKit
import SwiftUI

class KeyboardViewController: UIInputViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let (items, isLocked) = loadItems()
        let keyboardView = KeyboardView(
            items: items,
            isLocked: isLocked,
            onInsert: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            onNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            },
            needsInputModeSwitchKey: needsInputModeSwitchKey
        )

        let hostingController = UIHostingController(rootView: keyboardView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.heightAnchor.constraint(equalToConstant: 260)
        ])
    }

    private func loadItems() -> (items: [KeyboardItem], isLocked: Bool) {
        // Check if locked first (without triggering biometric)
        if ExtensionDataProvider.isLocked() {
            return ([], true)
        }

        // Load and decrypt items
        guard let decryptedItems = ExtensionDataProvider.loadDecryptedItems() else {
            return ([], true) // Locked or biometric failed
        }

        let keyboardItems = decryptedItems.prefix(10).map { KeyboardItem(id: $0.id, text: $0.text) }
        return (Array(keyboardItems), false)
    }
}

// MARK: - Keyboard Item Model

struct KeyboardItem: Codable, Identifiable {
    let id: String
    let text: String
}

// MARK: - SwiftUI Keyboard View

struct KeyboardView: View {
    let items: [KeyboardItem]
    let isLocked: Bool
    let onInsert: (String) -> Void
    let onNextKeyboard: () -> Void
    let needsInputModeSwitchKey: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundStyle(.purple)
                Text("Groo Pad")
                    .font(.headline)
                Spacer()

                if needsInputModeSwitchKey {
                    Button(action: onNextKeyboard) {
                        Image(systemName: "globe")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))

            // Content
            if isLocked {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.purple)
                    Text("Pad Locked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Open Groo to unlock")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else if items.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No items yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Open Groo to add items")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { item in
                            Button {
                                onInsert(item.text)
                            } label: {
                                HStack {
                                    Text(item.text)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Color(.systemGray4))
    }
}
