import SwiftUI
import UIKit
import TenantAPI

/// A photo of an issue, full screen: downloaded with the session token (the URL alone is not
/// openable — the tenant API has no cookies), pinch to zoom. Presented as a sheet from a
/// thumbnail in the thread.
struct IssuePhotoViewer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.l10n) private var l10n
    @Environment(\.dismiss) private var dismiss
    let issueId: String
    let documentId: String

    @State private var file: DownloadedFile?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let file {
                    if file.isImage, let image = UIImage(data: file.data) {
                        ZoomableImage(image: image)
                    } else {
                        ContentUnavailableView(l10n["issues.photoUnavailable"], systemImage: "photo")
                    }
                } else if let error {
                    VStack(spacing: 16) {
                        NoticeLabel(text: error)
                        Button(l10n["common.retry"]) { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                    .padding(24)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TenantTheme.surface)
            .navigationTitle(l10n["issues.thread.photo"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n["common.done"]) { dismiss() }
                }
            }
            .task { if file == nil { await load() } }
        }
    }

    private func load() async {
        error = nil
        do {
            file = try await app.client.issuePhoto(issueId: issueId, documentId: documentId)
        } catch {
            self.error = l10n.message(for: error)
        }
    }
}

/// The photos of the report or of a message as 64 pt thumbnails; tap one to open the viewer.
struct IssuePhotoStrip: View {
    let issueId: String
    let documentIds: [String]
    let onTap: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(documentIds, id: \.self) { documentId in
                Button {
                    onTap(documentId)
                } label: {
                    IssuePhotoThumbnail(issueId: issueId, documentId: documentId)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One photo thumbnail, downloaded with the session token and downscaled off the main thread.
struct IssuePhotoThumbnail: View {
    @Environment(AppModel.self) private var app
    let issueId: String
    let documentId: String
    var size: CGFloat = 64

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TenantTheme.neutralBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .foregroundStyle(TenantTheme.muted)
            } else {
                ProgressView()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task { await load() }
    }

    private func load() async {
        guard image == nil, !failed else { return }
        do {
            let file = try await app.client.issuePhoto(issueId: issueId, documentId: documentId)
            let data = file.data
            let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let full = UIImage(data: data) else { return nil }
                return ProofImport.downscaled(full, maxSide: 400)
            }.value
            image = decoded
            failed = decoded == nil
        } catch {
            failed = true
        }
    }
}
