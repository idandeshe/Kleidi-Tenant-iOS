@preconcurrency import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import TenantAPI
import TenantCore

/// Where a proof of transfer or an issue photo is picked from. Same three sources as the staff
/// app's document picker: camera, photo library, Files.
enum ProofPickerSource: Hashable {
    case camera, photos, files

    static var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
}

/// What a picked file must satisfy — the server whitelist and size limit of the upload it is
/// for: `.wireProof` on the Declare screen (PDF allowed, 15 MB), `.issuePhoto` on an issue
/// (images only, 10 MB).
struct ProofPickerRules: Sendable {
    let mimeTypes: Set<String>
    let maxBytes: Int
    /// Localizable key of the "wrong type" line (also the field hint) and of the "too large" line.
    let typeHintKey: String
    let tooLargeKey: String
    /// The stem of a camera / library file name ("Proof 26-10-2026 14.30.jpg").
    let fileNamePrefix: String

    static let wireProof = ProofPickerRules(
        mimeTypes: WireProofRules.mimeTypes, maxBytes: WireProofRules.maxBytes,
        typeHintKey: "wire.proofHint", tooLargeKey: "wire.proofTooLarge", fileNamePrefix: "Proof")

    static let issuePhoto = ProofPickerRules(
        mimeTypes: IssuePhotoRules.mimeTypes, maxBytes: IssuePhotoRules.maxBytes,
        typeHintKey: "issues.photoHint", tooLargeKey: "issues.photoTooLarge", fileNamePrefix: "Photo")

    /// What the Files picker offers.
    var contentTypes: [UTType] { mimeTypes.sorted().compactMap { UTType(mimeType: $0) } }

    func accepts(mimeType: String) -> Bool { mimeTypes.contains(mimeType.lowercased()) }

    /// MIME type for a file picked from Files; nil when the server would refuse it.
    func mimeType(forExtension ext: String) -> String? {
        guard let mimeType = WireProofRules.mimeType(forExtension: ext), accepts(mimeType: mimeType) else { return nil }
        return mimeType
    }
}

/// A camera / photos / Files menu that sets the source to present (pair it with `.proofPicker`).
struct ProofPickerMenu<Label: View>: View {
    @Environment(\.l10n) private var l10n
    @Binding var source: ProofPickerSource?
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            if ProofPickerSource.cameraAvailable {
                Button { source = .camera } label: { SwiftUI.Label(l10n["wire.proof.camera"], systemImage: "camera") }
            }
            Button { source = .photos } label: { SwiftUI.Label(l10n["wire.proof.photos"], systemImage: "photo.on.rectangle") }
            Button { source = .files } label: { SwiftUI.Label(l10n["wire.proof.files"], systemImage: "folder") }
        } label: {
            label()
        }
    }
}

extension View {
    /// Presents the camera, the photo library or the Files picker while `source` is set, and hands
    /// back a file the server accepts under `rules` — or the localized reason it can't be used (type,
    /// size, unreadable). Camera shots and HEIC / JPEG photos are re-encoded as JPEG (no location
    /// metadata); PNG and WebP photos and files are sent as they are.
    func proofPicker(_ source: Binding<ProofPickerSource?>,
                     rules: ProofPickerRules = .wireProof,
                     onPick: @escaping @MainActor (UploadFile) -> Void,
                     onProblem: @escaping @MainActor (String) -> Void) -> some View {
        modifier(ProofPickerModifier(source: source, rules: rules, onPick: onPick, onProblem: onProblem))
    }
}

private struct ProofPickerModifier: ViewModifier {
    @Environment(\.l10n) private var l10n
    @Binding var source: ProofPickerSource?
    let rules: ProofPickerRules
    let onPick: @MainActor (UploadFile) -> Void
    let onProblem: @MainActor (String) -> Void
    @State private var photoItem: PhotosPickerItem?

    private func presented(_ value: ProofPickerSource) -> Binding<Bool> {
        Binding(get: { source == value }, set: { if !$0, source == value { source = nil } })
    }

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: presented(.files), allowedContentTypes: rules.contentTypes) { result in
                switch result {
                case .success(let url): readFile(url)
                case .failure: onProblem(l10n["wire.proofUnreadable"])
                }
            }
            .photosPicker(isPresented: presented(.photos), selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .fullScreenCover(isPresented: presented(.camera)) {
                ProofCameraPicker { image in
                    acceptImage(image)
                }
                .ignoresSafeArea()
            }
    }

    private func accept(_ data: Data, fileName: String, mimeType: String) {
        guard rules.accepts(mimeType: mimeType) else {
            onProblem(l10n[rules.typeHintKey])
            return
        }
        guard data.count <= rules.maxBytes else {
            onProblem(l10n[rules.tooLargeKey])
            return
        }
        onPick(UploadFile(data: data, fileName: fileName, mimeType: mimeType))
    }

    private func acceptImage(_ image: UIImage) {
        guard let data = ProofImport.jpegData(image, maxBytes: rules.maxBytes) else {
            onProblem(l10n[rules.tooLargeKey])
            return
        }
        accept(data, fileName: ProofImport.stampedName(prefix: rules.fileNamePrefix, extension: "jpg"), mimeType: "image/jpeg")
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                onProblem(l10n["wire.proofUnreadable"])
                return
            }
            let types = item.supportedContentTypes
            if types.contains(where: { $0.conforms(to: .png) }) {
                accept(data, fileName: ProofImport.stampedName(prefix: rules.fileNamePrefix, extension: "png"), mimeType: "image/png")
            } else if types.contains(where: { $0.conforms(to: .webP) }) {
                accept(data, fileName: ProofImport.stampedName(prefix: rules.fileNamePrefix, extension: "webp"), mimeType: "image/webp")
            } else if let image = UIImage(data: data) {
                // JPEG and HEIC (the camera's default) both go out as JPEG.
                acceptImage(image)
            } else {
                onProblem(l10n[rules.typeHintKey])
            }
        } catch {
            onProblem(l10n["wire.proofUnreadable"])
        }
    }

    private func readFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let mimeType = rules.mimeType(forExtension: url.pathExtension) else {
            onProblem(l10n[rules.typeHintKey])
            return
        }
        // Check the size before reading a possibly huge file into memory.
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > rules.maxBytes {
            onProblem(l10n[rules.tooLargeKey])
            return
        }
        do {
            accept(try Data(contentsOf: url), fileName: url.lastPathComponent, mimeType: mimeType)
        } catch {
            onProblem(l10n["wire.proofUnreadable"])
        }
    }
}

/// Turns a picked image into the JPEG the server accepts.
enum ProofImport {
    static let jpegQuality: CGFloat = 0.85
    /// Longest side after downscaling, when the full-size JPEG would exceed the limit.
    static let maxSide: CGFloat = 2000

    /// JPEG at 0.85; if that is still over `maxBytes`, downscaled so the longest side is
    /// 2000 px. nil when even the downscaled JPEG is too large (practically never).
    static func jpegData(_ image: UIImage, maxBytes: Int = WireProofRules.maxBytes) -> Data? {
        if let data = image.jpegData(compressionQuality: jpegQuality), data.count <= maxBytes {
            return data
        }
        guard let smaller = downscaled(image, maxSide: maxSide),
              let data = smaller.jpegData(compressionQuality: jpegQuality),
              data.count <= maxBytes else { return nil }
        return data
    }

    /// The image with its longest side at most `maxSide` pixels (orientation baked in).
    static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > 0 else { return nil }
        let factor = min(1, maxSide / longest)
        let target = CGSize(width: (pixelSize.width * factor).rounded(.down), height: (pixelSize.height * factor).rounded(.down))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// "Proof 26-10-2026 14.30.jpg" — a file name for a camera / library image (no slashes or colons).
    static func stampedName(prefix: String = "Proof", extension ext: String, now: Date = Date()) -> String {
        let day = TenantFormatter.date(now).replacingOccurrences(of: "/", with: "-")
        let time = now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "en_GB")))
            .replacingOccurrences(of: ":", with: ".")
        return "\(prefix) \(day) \(time).\(ext)"
    }
}

/// The system camera, photo mode; hands back the shot and dismisses itself.
struct ProofCameraPicker: UIViewControllerRepresentable {
    let onCapture: @MainActor (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        let dismiss = dismiss
        return Coordinator(onCapture: onCapture, onFinish: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: @MainActor (UIImage) -> Void
        let onFinish: @MainActor () -> Void

        init(onCapture: @escaping @MainActor (UIImage) -> Void, onFinish: @escaping @MainActor () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
