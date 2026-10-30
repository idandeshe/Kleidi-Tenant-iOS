import SwiftUI
import TenantAPI
import TenantCore

/// One issue's thread: the header with the status pill, the report card with its photos,
/// "Received · date", then the messages — the tenant's on the right in accent, the property
/// manager's on the left, status changes centred. While the issue is open a composer sends a
/// text and / or up to three photos; once resolved or closed the composer gives way to a note
/// and a "Report it again" link. Opening the thread marks it seen on the server. While the
/// thread is on screen and the app is active it re-reads itself every few seconds, so the
/// property manager's replies and status changes appear on their own.
struct IssueDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase
    let id: String

    /// How often the open thread is re-read (the web and Android apps use the same).
    private static let pollInterval: Duration = .seconds(5)

    @State private var detail: TenantIssueDetail?
    @State private var error: String?
    @State private var reply = ""
    @State private var replyPhotos: [PickedPhoto] = []
    @State private var pickerSource: ProofPickerSource?
    @State private var sendError: String?
    @State private var isSending = false
    @State private var viewing: IssuePhotoRef?
    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if let detail {
                thread(detail)
            } else if let error {
                VStack(spacing: 16) {
                    NoticeLabel(text: error)
                    Button(l10n["common.retry"]) { Task { await load() } }
                        .buttonStyle(.bordered)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(TenantTheme.ground)
        .navigationTitle(l10n["issues.detail.title"])
        .navigationBarTitleDisplayMode(.inline)
        .task { if detail == nil { await load() } }
        // Cancelled when the thread leaves the screen; skipped while the app is in the background.
        .task(id: id) {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, scenePhase == .active else { continue }
                await poll()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, detail != nil { Task { await poll() } }
        }
        .sheet(item: $viewing) { IssuePhotoViewer(issueId: $0.issueId, documentId: $0.documentId) }
        .proofPicker($pickerSource, rules: .issuePhoto, onPick: { picked in
            guard replyPhotos.count < IssuePhotoRules.maxReplyPhotos else { return }
            replyPhotos.append(PickedPhoto(file: picked))
            sendError = nil
        }, onProblem: { problem in
            sendError = problem
        })
    }

    private func thread(_ detail: TenantIssueDetail) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        IssueHeader(issue: detail.issue)
                        ReportCard(issue: detail.issue) { documentId in
                            viewing = IssuePhotoRef(issueId: detail.id, documentId: documentId)
                        }
                        Text(l10n.format("issues.detail.received", TenantFormatter.dateTime(detail.issue.createdAt)))
                            .font(.caption)
                            .foregroundStyle(TenantTheme.muted)
                            .frame(maxWidth: .infinity)
                        // The report line above already says "Received"; a `new` status event would repeat it.
                        ForEach(detail.messages.filter { !($0.isStatusEvent && $0.status == .new) }) { message in
                            IssueThreadRow(message: message, issueId: detail.id) { documentId in
                                viewing = IssuePhotoRef(issueId: detail.id, documentId: documentId)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(20)
                }
                .refreshable { await load() }
                .onChange(of: detail.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: composerFocused) { _, focused in
                    if focused { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
            }
            Divider()
            if detail.issue.canReply {
                composer
            } else {
                closedNote(detail.issue)
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if let sendError {
                NoticeLabel(text: sendError)
            }
            if !replyPhotos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(replyPhotos) { photo in
                        PickedPhotoTile(photo: photo) {
                            replyPhotos.removeAll { $0.id == photo.id }
                        }
                        .frame(width: 56, height: 56)
                    }
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ProofPickerMenu(source: $pickerSource) {
                    Image(systemName: "camera")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(TenantTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(TenantTheme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TenantTheme.hairline))
                }
                .disabled(replyPhotos.count >= IssuePhotoRules.maxReplyPhotos)
                .accessibilityLabel(l10n["issues.report.addPhoto"])
                TextField(l10n["issues.composer.placeholder"], text: $reply, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(TenantTheme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TenantTheme.hairline))
                    .onChange(of: reply) { _, value in
                        if value.count > IssuePhotoRules.messageMaxLength {
                            reply = String(value.prefix(IssuePhotoRules.messageMaxLength))
                        }
                    }
                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up").font(.body.weight(.bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(TenantTheme.accent.opacity(canSend ? 1 : 0.35),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(!canSend)
                .accessibilityLabel(l10n["issues.composer.send"])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(TenantTheme.ground)
    }

    /// Text or at least one photo, and nothing in flight.
    private var canSend: Bool {
        !isSending && (IssueReplyDraft(body: reply).trimmedBody != nil || !replyPhotos.isEmpty)
    }

    private func closedNote(_ issue: TenantIssue) -> some View {
        VStack(spacing: 6) {
            Text(l10n["issues.repliesClosed"])
                .font(.caption)
                .foregroundStyle(TenantTheme.muted)
                .multilineTextAlignment(.center)
            NavigationLink(value: Route.reportIssue(leaseId: issue.leaseId)) {
                Text(l10n["issues.reportAgain"])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TenantTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Loading and sending

    private func load() async {
        error = nil
        do {
            apply(try await app.client.issue(id: id))
        } catch {
            if detail == nil { self.error = l10n.message(for: error) }
        }
    }

    /// A silent re-read: what comes back replaces the thread, a failure changes nothing on screen.
    private func poll() async {
        guard let fresh = try? await app.client.issue(id: id) else { return }
        apply(fresh)
    }

    /// Shows the thread. The list underneath reloads (its "new reply" dot, the status pill) when the
    /// thread was first opened — that marks it seen — or when something in it changed, not on every poll.
    private func apply(_ fresh: TenantIssueDetail) {
        let changed = detail.map { $0.messages.count != fresh.messages.count || $0.issue.status != fresh.issue.status } ?? true
        detail = fresh
        if changed { navigation.issuesDidChange() }
    }

    private func send() async {
        guard let detail, canSend else { return }
        sendError = nil
        isSending = true
        defer { isSending = false }
        do {
            _ = try await app.client.replyToIssue(id: detail.id, draft: IssueReplyDraft(body: reply), photos: replyPhotos.map(\.file))
            reply = ""
            replyPhotos = []
            await load()
        } catch let apiError as APIError where apiError.status == 409 {
            // Resolved or closed meanwhile: reload so the composer gives way to the note.
            sendError = l10n["issues.repliesClosed"]
            await load()
        } catch let apiError as APIError where apiError.status == 413 {
            sendError = l10n["issues.photoTooLarge"]
        } catch let apiError as APIError where apiError.status == 415 {
            sendError = l10n["issues.photoHint"]
        } catch {
            sendError = l10n.message(for: error)
        }
    }
}

/// A photo to open full-screen: the issue it belongs to and the document.
struct IssuePhotoRef: Identifiable, Hashable {
    let issueId: String
    let documentId: String

    var id: String { "\(issueId)/\(documentId)" }
}

// MARK: - Header and report

/// Summary, "Plumbing · reported 27/10/2026", the status pill; the urgent line while open;
/// "Resolved on <date>" or "Closed by management · <reason>" once settled.
private struct IssueHeader: View {
    @Environment(\.l10n) private var l10n
    let issue: TenantIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.summary)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(TenantTheme.ink)
                    Text(l10n.format("issues.reportedOn", issue.category.label(l10n), TenantFormatter.date(issue.createdAt)))
                        .font(.caption)
                        .foregroundStyle(TenantTheme.muted)
                }
                Spacer(minLength: 8)
                IssueStatusPill(status: issue.status)
            }
            if issue.isUrgent && issue.status.isOpen {
                Label(l10n["issues.urgent"], systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TenantTheme.errorInk)
            }
            if issue.status == .resolved, let date = issue.resolvedAt {
                AlertBox(text: l10n.format("issues.detail.resolvedOn", TenantFormatter.date(date)), tone: .ok)
            }
            if issue.status == .closed {
                AlertBox(
                    text: issue.closeReason.map { l10n.format("issues.detail.closedBy", $0) } ?? l10n["issues.detail.closed"],
                    tone: .neutral)
            }
        }
    }
}

/// The tenant's own report: the description and the photos they attached.
private struct ReportCard: View {
    let issue: TenantIssue
    let onPhoto: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(issue.description)
                .font(.subheadline)
                .foregroundStyle(TenantTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !issue.photoDocumentIds.isEmpty {
                IssuePhotoStrip(issueId: issue.id, documentIds: issue.photoDocumentIds, onTap: onPhoto)
            }
        }
        .card()
    }
}

// MARK: - Thread rows

/// One thread entry: a status change centred in its status colour, a tenant message as an
/// accent bubble on the right ("You · date time"), a staff message as a white bubble on the
/// left ("Property manager · date time"). Tenant photos sit inside the bubble.
struct IssueThreadRow: View {
    @Environment(\.l10n) private var l10n
    let message: TenantIssueMessage
    let issueId: String
    let onPhoto: (String) -> Void

    var body: some View {
        if message.isStatusEvent {
            statusEvent
        } else {
            bubble(isTenant: message.isFromTenant)
        }
    }

    private var statusEvent: some View {
        let status = message.status ?? .new
        let tone = IssueTones.tone(for: status)
        return VStack(spacing: 2) {
            Text(l10n.format("issues.thread.statusChanged", status.label(l10n), TenantFormatter.date(message.createdAt)))
            if status == .closed, let reason = message.closeReason ?? message.body, !reason.isEmpty {
                Text(reason)
            }
        }
        .font(.caption)
        .foregroundStyle(tone.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func bubble(isTenant: Bool) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: isTenant ? 14 : 4,
            bottomTrailingRadius: isTenant ? 4 : 14,
            topTrailingRadius: 14,
            style: .continuous)
        return VStack(alignment: isTenant ? .trailing : .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 8) {
                if let body = message.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(isTenant ? Color.white : TenantTheme.ink)
                }
                if !message.photoDocumentIds.isEmpty {
                    IssuePhotoStrip(issueId: issueId, documentIds: message.photoDocumentIds, onTap: onPhoto)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isTenant ? TenantTheme.accent : TenantTheme.ground, in: shape)
            .overlay {
                if !isTenant {
                    shape.stroke(TenantTheme.hairline)
                }
            }
            Text("\(l10n[isTenant ? "issues.thread.you" : "issues.thread.staff"]) · \(TenantFormatter.dateTime(message.createdAt))")
                .font(.caption2)
                .foregroundStyle(TenantTheme.muted)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: 300, alignment: isTenant ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: isTenant ? .trailing : .leading)
    }
}
