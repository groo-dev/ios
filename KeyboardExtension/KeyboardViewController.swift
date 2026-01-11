//
//  KeyboardViewController.swift
//  KeyboardExtension
//
//  Custom keyboard that shows recent Pad items for quick insertion.
//

import UIKit
import SwiftUI

class KeyboardViewController: UIInputViewController {

    private var appGroupId: String {
        #if DEBUG
        "group.dev.groo.ios.debug"
        #else
        "group.dev.groo.ios"
        #endif
    }

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
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else { return ([], true) }

        let cacheURL = containerURL.appendingPathComponent("widget_cache.json")

        guard let data = try? Data(contentsOf: cacheURL),
              let items = try? JSONDecoder().decode([KeyboardItem].self, from: data) else {
            // No cache file means Pad is locked
            return ([], true)
        }

        return (Array(items.prefix(10)), false)
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
