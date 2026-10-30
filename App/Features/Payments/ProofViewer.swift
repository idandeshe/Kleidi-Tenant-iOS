import PDFKit
import SwiftUI
import TenantAPI

/// "View proof": downloads the declaration's file with the session token (the URL alone is
/// not openable — the tenant API has no cookies) and shows it, images inline and PDFs
/// through PDFKit. Presented as a sheet from a month row on Payments.
struct ProofViewer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.l10n) private var l10n
    @Environment(\.dismiss) private var dismiss
    let declarationId: String

    @State private var proof: WireProofFile?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let proof {
                    if proof.isPDF {
                        PDFKitView(data: proof.data)
                            .ignoresSafeArea(edges: .bottom)
                    } else if proof.isImage, let image = UIImage(data: proof.data) {
                        ZoomableImage(image: image)
                    } else {
                        ContentUnavailableView(l10n["rent.proofUnavailable"], systemImage: "doc")
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
            .navigationTitle(l10n["rent.viewProof"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n["common.done"]) { dismiss() }
                }
            }
            .task { if proof == nil { await load() } }
        }
    }

    private func load() async {
        error = nil
        do {
            proof = try await app.client.wireProof(declarationId: declarationId)
        } catch {
            self.error = l10n.message(for: error)
        }
    }
}

/// A PDF proof, page by page, fitted to the width.
private struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(TenantTheme.surface)
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

/// A photo or screenshot proof: fitted, pinch to zoom, double-tap to reset.
private struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .containerRelativeFrame([.horizontal, .vertical]) { length, _ in length * scale }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    scale = min(max(lastScale * value.magnification, 1), 5)
                }
                .onEnded { _ in lastScale = scale }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                scale = 1
                lastScale = 1
            }
        }
    }
}
