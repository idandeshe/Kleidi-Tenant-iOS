import SwiftUI
import TenantAPI
import TenantCore

/// "I paid by bank transfer": pick the months, say how much and when, attach the bank
/// confirmation (required) and send. The declaration goes to the property manager's review
/// queue; the months show as "declared" until then. Mirrors the web `DeclareWirePage`.
struct DeclareWireView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.l10n) private var l10n
    @Environment(\.dismiss) private var dismiss
    let leaseId: String

    @State private var rent: TenantRent?
    @State private var loadError: String?
    @State private var selected: Set<String> = []
    @State private var amountText = ""
    /// The amount follows the picked months until the tenant types in the field.
    @State private var amountEdited = false
    @State private var transferDate = Date()
    @State private var reference = ""
    @State private var proof: WireProofUpload?
    @State private var pickerSource: ProofPickerSource?
    @State private var error: String?
    @State private var isSubmitting = false
    @State private var done = false
    @FocusState private var focused: Field?

    private enum Field { case amount, reference }

    var body: some View {
        Group {
            if done {
                DeclareWireDoneView(
                    onPayments: { finish(switchingTo: .payments) },
                    onHome: { finish(switchingTo: .home) })
            } else {
                form
            }
        }
        .background(TenantTheme.ground)
        .navigationTitle(l10n["wire.title"])
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(done)
        .task { if rent == nil { await load() } }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(l10n["wire.intro"])
                    .font(.subheadline)
                    .foregroundStyle(TenantTheme.muted)

                if let rent {
                    let declarable = rent.declarableMonths
                    if declarable.isEmpty {
                        AlertBox(text: l10n["rent.nothingToDeclare"], tone: .accent)
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            if let error {
                                NoticeLabel(text: error)
                            }
                            monthsSection(declarable, currencyCode: rent.currencyCode)
                            amountSection(declarable, currencyCode: rent.currencyCode)
                            dateSection
                            referenceSection
                            proofSection
                            Button {
                                Task { await submit() }
                            } label: {
                                if isSubmitting {
                                    Text(l10n["wire.submitting"])
                                } else {
                                    Label(l10n["wire.submit"], systemImage: "building.columns")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(isSubmitting)
                            Button(l10n["wire.cancel"]) { dismiss() }
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .disabled(isSubmitting)
                        }
                        .card()
                    }
                } else if let loadError {
                    NoticeLabel(text: loadError)
                    Button(l10n["common.retry"]) { Task { await load() } }
                        .buttonStyle(.bordered)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .proofPicker($pickerSource, onPick: { picked in
            proof = picked
            error = nil
        }, onProblem: { problem in
            error = problem
        })
    }

    // MARK: Sections

    private func monthsSection(_ declarable: [TenantRentMonth], currencyCode: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: l10n["wire.monthsLabel"], hint: l10n["wire.monthsHint"])
            ForEach(declarable) { month in
                let isSelected = selected.contains(month.period)
                Button {
                    toggle(month.period, in: declarable)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(isSelected ? TenantTheme.accent : TenantTheme.muted)
                        Text(TenantFormatter.period(month.period, language: l10n.language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TenantTheme.ink)
                        Spacer()
                        if let expected = month.expectedAmount {
                            Text(TenantFormatter.money(expected, currencyCode: currencyCode, language: l10n.language))
                                .font(.subheadline)
                                .foregroundStyle(TenantTheme.muted)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(isSelected ? TenantTheme.accentBackground : TenantTheme.surface,
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

    private func amountSection(_ declarable: [TenantRentMonth], currencyCode: String?) -> some View {
        let expected = expectedTotal(declarable)
        return VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: l10n["wire.amountLabel"])
            TextField("0", text: amountBinding)
                .keyboardType(.decimalPad)
                .focused($focused, equals: .amount)
                .field()
                .accessibilityLabel(l10n["wire.amountLabel"])
            if expected > 0 {
                Text(l10n.format("wire.amountHint", TenantFormatter.money(expected, currencyCode: currencyCode, language: l10n.language)))
                    .font(.footnote)
                    .foregroundStyle(TenantTheme.muted)
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: l10n["wire.dateLabel"])
            DatePicker(l10n["wire.dateLabel"], selection: $transferDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.locale, l10n.language.locale)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: l10n["wire.referenceLabel"])
            TextField(l10n["wire.referencePlaceholder"], text: $reference)
                .font(.body)
                .focused($focused, equals: .reference)
                .field()
                .onChange(of: reference) { _, value in
                    if value.count > WireProofRules.referenceMaxLength {
                        reference = String(value.prefix(WireProofRules.referenceMaxLength))
                    }
                }
        }
    }

    private var proofSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: l10n["wire.proofLabel"], hint: l10n["wire.proofHint"])
            ProofPickerMenu(source: $pickerSource) {
                Label(l10n[proof == nil ? "wire.proofPick" : "wire.proofChange"], systemImage: "paperclip")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TenantTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(TenantTheme.accentBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let proof {
                Text("\(proof.fileName) · \(TenantFormatter.fileSize(proof.data.count, language: l10n.language))")
                    .font(.footnote)
                    .foregroundStyle(TenantTheme.muted)
                    .lineLimit(2)
            }
        }
    }

    // MARK: State

    /// Typing marks the amount as the tenant's own; picking months no longer overwrites it.
    private var amountBinding: Binding<String> {
        Binding(
            get: { amountText },
            set: { value in
                if value != amountText { amountEdited = true }
                amountText = value
            })
    }

    private func toggle(_ period: String, in declarable: [TenantRentMonth]) {
        if selected.contains(period) {
            selected.remove(period)
        } else {
            selected.insert(period)
        }
        guard !amountEdited else { return }
        let sum = expectedTotal(declarable)
        amountText = sum > 0
            ? sum.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(l10n.language.locale))
            : ""
    }

    private func expectedTotal(_ declarable: [TenantRentMonth]) -> Double {
        declarable.filter { selected.contains($0.period) }.reduce(0) { $0 + ($1.expectedAmount ?? 0) }
    }

    /// "812,50" or "812.50" → 812.5; nil when empty, malformed or not positive.
    private var amountValue: Decimal? {
        let normalized = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty,
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }

    private func load() async {
        loadError = nil
        do {
            rent = try await app.client.rent(leaseId: leaseId)
        } catch {
            loadError = l10n.message(for: error)
        }
    }

    private func submit() async {
        guard let rent, !isSubmitting else { return }
        error = nil
        focused = nil
        let periods = selected.sorted()
        guard !periods.isEmpty else {
            error = l10n["wire.monthsRequired"]
            return
        }
        guard let amount = amountValue else {
            error = l10n["wire.amountRequired"]
            return
        }
        guard let proof else {
            error = l10n["wire.proofRequired"]
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = WireDeclarationDraft(
            periods: periods,
            declaredAmount: amount,
            transferDate: transferDate,
            reference: trimmedReference.isEmpty ? nil : trimmedReference,
            proof: proof)
        do {
            _ = try await app.client.declareWire(leaseId: rent.leaseId, draft)
            navigation.rentDidChange()
            done = true
        } catch let apiError as APIError where apiError.status == 413 {
            error = l10n["wire.proofTooLarge"]
        } catch let apiError as APIError where apiError.status == 415 {
            error = l10n["wire.proofHint"]
        } catch {
            self.error = l10n.message(for: error)
        }
    }

    /// Leaves the screen and lands on the chosen tab.
    private func finish(switchingTo tab: AppNavigation.Tab) {
        dismiss()
        navigation.tab = tab
    }
}

/// A field caption, optionally with a hint under it.
private struct FieldLabel: View {
    let text: String
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TenantTheme.ink)
            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(TenantTheme.muted)
            }
        }
    }
}

/// The success state: the declaration is with the property manager.
private struct DeclareWireDoneView: View {
    @Environment(\.l10n) private var l10n
    let onPayments: () -> Void
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "building.columns")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(TenantTheme.okInk)
                .frame(width: 64, height: 64)
                .background(TenantTheme.okBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(l10n["wire.doneTitle"])
                .font(.title3.weight(.semibold))
                .foregroundStyle(TenantTheme.ink)
            Text(l10n["wire.doneBody"])
                .font(.subheadline)
                .foregroundStyle(TenantTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
            Button(l10n["tab.payments"], action: onPayments)
                .buttonStyle(PrimaryButtonStyle())
            Button(l10n["wire.backHome"], action: onHome)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
