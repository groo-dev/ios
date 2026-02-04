//
//  FileAttachmentView.swift
//  Groo
//
//  File attachment display with download and preview support.
//

import SwiftUI
import WebKit

// MARK: - File Icon Helper

enum FileIconHelper {
    static func icon(for mimeType: String) -> String {
        let type = mimeType.lowercased()

        if type.hasPrefix("image/") {
            return "photo"
        } else if type.hasPrefix("video/") {
            return "video"
        } else if type.hasPrefix("audio/") {
            return "waveform"
        } else if type == "application/pdf" {
            return "doc.text"
        } else if type.contains("zip") || type.contains("archive") || type.contains("compressed") {
            return "doc.zipper"
        } else if type.contains("text") || type.contains("json") || type.contains("xml") {
            return "doc.plaintext"
        } else if type.contains("spreadsheet") || type.contains("excel") {
            return "tablecells"
        } else if type.contains("presentation") || type.contains("powerpoint") {
            return "play.rectangle"
        } else if type.contains("word") || type.contains("document") {
            return "doc.richtext"
        }

        return "doc"
    }

    static func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - File Attachment Chip

struct FileAttachmentChip: View {
    let file: DecryptedFileAttachment
    let padService: PadService

    @State private var isDownloading = false
    @State private var previewData: Data?
    @State private var showPreview = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            downloadAndPreview()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                ZStack {
                    Image(systemName: FileIconHelper.icon(for: file.type))
                        .font(.system(size: Theme.Size.iconSM))
                        .foregroundStyle(Theme.Brand.primary)
                        .opacity(isDownloading ? 0 : 1)

                    if isDownloading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .frame(width: Theme.Size.iconMD, height: Theme.Size.iconMD)

                VStack(alignment: .leading, spacing: 0) {
                    Text(file.name)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Text(FileIconHelper.formatSize(file.size))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
        .sheet(isPresented: $showPreview) {
            if let data = previewData {
                FilePreviewSheet(
                    data: data,
                    mimeType: file.type,
                    fileName: file.name
                )
            }
        }
    }

    private func downloadAndPreview() {
        guard !isDownloading else { return }

        isDownloading = true
        errorMessage = nil

        Task {
            do {
                let data = try await padService.downloadFile(file)
                previewData = data
                showPreview = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isDownloading = false
        }
    }
}

// MARK: - File Preview Sheet

struct FilePreviewSheet: View {
    let data: Data
    let mimeType: String
    let fileName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FilePreviewWebView(data: data, mimeType: mimeType)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(fileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - File Preview WebView

struct FilePreviewWebView: UIViewRepresentable {
    let data: Data
    let mimeType: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .systemBackground
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.load(
            data,
            mimeType: mimeType,
            characterEncodingName: "utf-8",
            baseURL: URL(string: "about:blank")!
        )
    }
}

// MARK: - File Attachments Grid

struct FileAttachmentsGrid: View {
    let files: [DecryptedFileAttachment]
    let padService: PadService

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.xs) {
            ForEach(files) { file in
                FileAttachmentChip(file: file, padService: padService)
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxX: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                maxX = max(maxX, currentX - spacing)
            }

            size = CGSize(width: maxX, height: currentY + lineHeight)
        }
    }
}

// MARK: - Pending File Model

struct PendingFile: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let data: Data

    var size: Int { data.count }
}

// MARK: - Pending File Chip

struct PendingFileChip: View {
    let file: PendingFile
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: FileIconHelper.icon(for: file.type))
                .font(.system(size: Theme.Size.iconSM))
                .foregroundStyle(Theme.Brand.primary)

            VStack(alignment: .leading, spacing: 0) {
                Text(file.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(FileIconHelper.formatSize(file.size))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: Theme.Size.iconSM))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

#Preview {
    VStack(spacing: 20) {
        FileAttachmentChip(
            file: DecryptedFileAttachment(
                id: "1",
                name: "document.pdf",
                type: "application/pdf",
                size: 1024 * 512,
                r2Key: "test"
            ),
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL))
        )

        PendingFileChip(
            file: PendingFile(name: "photo.jpg", type: "image/jpeg", data: Data()),
            onRemove: {}
        )
    }
    .padding()
}
