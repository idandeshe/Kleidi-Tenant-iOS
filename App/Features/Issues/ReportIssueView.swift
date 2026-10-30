import SwiftUI
import UIKit
import TenantAPI
import TenantCore

/// "Report an issue": pick what it is about, describe it, add up to five photos, flag it as
/// urgent and send it to the property manager. On success the app lands on the new issue's
/// thread in the Issues tab (the form is popped when it was opened from Home).
struct ReportIssueView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.l10n) private var l10n
    @Environment(\.dismiss) private var dismiss
    let leaseId: String

    @State private var category: TenantIssueCategory?
    @State private var description = ""
    @State private var photos: [PickedPhoto] = []
    @State private var isUrgent = false
    @State private var pickerSource: ProofPickerSource?
    @State private var error: String?
    @State private var isSubmitting = false
    @FocusState private var descriptionFocused: Bool

    private let categoryColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let photoColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error {
                    NoticeLabel(text: error)
                }
                categorySection
                descriptionSection
                photosSection
                urgentToggle
                Button {
                    Task { await submit() }
                } label: {
                    Text(l10n[isSubmitting ? "issues.report.submitting" : "issues.report.submit"])
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSubmitting)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(TenantTheme.ground)
        .navigationTitle(l10n["issues.report"])
        .navigationBarTitleDisplayMode(.inline)
        .proofPicker($pickerSource, rules: .issuePhoto, onPick: { picked in
            guard photos.count < IssuePhotoRules.maxReportPhotos else { return }
            photos.append(PickedPhoto(file: picked))
            error = nil
        }, onProblem: { problem in
            error = problem
        })
    }

    // MARK: Sections

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: l10n["issues.report.categoryLabel"])
            LazyVGrid(columns: categoryColumns, spacing: 8) {
                ForEach(TenantIssueCategory.all, id: \.rawValue) { item in
                    let isSelected = category == item
                    Button {
                        category = item
                        error = nil
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.symbolName)
                                .font(.title3.weight(.semibold))
                            Text(item.label(l10n))
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(isSelected ? TenantTheme.accentInk : TenantTheme.ink)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(isSelected ? TenantTheme.accentBackground : TenantTheme.ground,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? TenantTheme.accent : TenantTheme.hairline, lineWidth: isSelected ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: l10n["issues.report.descriptionLabel"])
            TextField(l10n["issues.report.descriptionPlaceholder"], text: $description, axis: .vertical)
                .font(.body)
                .lineLimit(4...10)
                .focused($descriptionFocused)
                .padding(.vertical, 12)
                .field()
                .onChange(of: description) { _, value in
                    if value.count > IssuePhotoRules.descriptionMaxLength {
                        description = String(value.prefix(IssuePhotoRules.descriptionMaxLength))
                    }
                }
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: l10n["issues.report.photosLabel"],
                       hint: l10n.format("issues.report.photosHint", IssuePhotoRules.maxReportPhotos))
            LazyVGrid(columns: photoColumns, spacing: 8) {
                ForEach(photos) { photo in
                    PickedPhotoTile(photo: photo) {
                        photos.removeAll { $0.id == photo.id }
                    }
                }
                if photos.count < IssuePhotoRules.maxReportPhotos {
                    AddPhotoTile(source: $pickerSource)
                }
            }
        }
    }

    private var urgentToggle: some View {
        Toggle(isOn: $isUrgent) {
            Text(l10n["issues.report.urgent"])
                .font(.subheadline)
                .foregroundStyle(TenantTheme.ink)
        }
        .tint(TenantTheme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(TenantTheme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TenantTheme.hairline))
    }

    // MARK: Submit

    private func submit() async {
        guard !isSubmitting else { return }
        error = nil
        descriptionFocused = false
        guard let category else {
            error = l10n["issues.report.categoryRequired"]
            return
        }
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            error = l10n["issues.report.descriptionRequired"]
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let draft = ReportIssueDraft(category: category, description: text, isUrgent: isUrgent)
        do {
            let created = try await app.client.reportIssue(leaseId: leaseId, draft: draft, photos: photos.map(\.file))
            navigation.issuesDidChange()
            // Land on the new thread in the Issues tab; coming from Home, leave the form first
            // (in the Issues tab the path replacement pops it).
            if navigation.tab != .issues { dismiss() }
            navigation.showIssue(id: created.id)
        } catch let apiError as APIError where apiError.status == 413 {
            error = l10n["issues.photoTooLarge"]
        } catch let apiError as APIError where apiError.status == 415 {
            error = l10n["issues.photoHint"]
        } catch {
            self.error = l10n.message(for: error)
        }
    }
}

// MARK: - Picked photos

/// A photo the tenant picked for the report or a reply, with an identity for the grid.
struct PickedPhoto: Identifiable, Hashable {
    let id = UUID()
    let file: UploadFile
}

/// A picked photo as a square tile with its remove button. The thumbnail is decoded once,
/// downscaled, off the main thread.
struct PickedPhotoTile: View {
    @Environment(\.l10n) private var l10n
    let photo: PickedPhoto
    let onRemove: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .background(TenantTheme.neutralBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, TenantTheme.ink.opacity(0.7))
                }
                .padding(4)
                .accessibilityLabel(l10n["issues.report.removePhoto"])
            }
            .task(id: photo.id) {
                let data = photo.file.data
                thumbnail = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    guard let full = UIImage(data: data) else { return nil }
                    return ProofImport.downscaled(full, maxSide: 300)
                }.value
            }
    }
}

/// The dashed "add a photo" tile: camera, photo library or Files.
struct AddPhotoTile: View {
    @Environment(\.l10n) private var l10n
    @Binding var source: ProofPickerSource?

    var body: some View {
        ProofPickerMenu(source: $source) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(TenantTheme.accent)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TenantTheme.muted.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityLabel(l10n["issues.report.addPhoto"])
    }
}
