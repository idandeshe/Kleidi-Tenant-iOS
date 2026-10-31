# Kleidi Tenant iOS

Native SwiftUI app for **tenants** of properties managed with Kleidi: sign in with your phone
number and an SMS code, see your lease and this month's rent. Talks to the same Fastify server
as the staff app, through the tenant entrance `/api/tenant/*` (server repo: `docs/tenant-app.md`).
iOS 17+, iPhone only. Greek and English, chosen in the app.

Phase 1: language → phone + code sign-in → My lease (rent card, lease terms) → Profile.
Phase 2: rent months with their state, "I paid by bank transfer" (months, amount, date, proof
photo / PDF) and the declaration history on the Payments tab.
Phase 3: Issues — report a maintenance issue (category, description, up to five photos, urgent
flag), follow it in a thread with the property manager and reply while it is open. Online payment
is still a placeholder.

| Feature | Status |
|---------|--------|
| Language, phone + SMS-code sign-in, forced update | Built |
| Home ("My lease"), lease terms, Profile | Built |
| Payments: rent months, "I paid by bank transfer", proof viewer | Built |
| Pay online | Placeholder ("Coming soon") |
| Issues: list, report, thread with replies and photos | Built, not yet compiled in Xcode |

## Layout

| Path | What |
|------|------|
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated, never committed. |
| `Design/AppIcon.svg` | App icon source (the staff app's key on a blue gradient). Export at 1024×1024, opaque, to `App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. |
| `Config/*.xcconfig` | Per-environment server URL, environment name and bundle id (Debug → dev `app.kleidi.tenant.dev`, Stage → `…stage`, Release → prod `app.kleidi.tenant`). |
| `App/` | The app target: `Shell/` (app model, root / tabs + `AppNavigation`, routes, theme, localization plumbing, server environment) and `Features/` (Language, Auth, Home, Payments, Issues, Profile). |
| `App/Features/Payments/` | `PaymentsView` (declare button, Pay-online placeholder, "Rent" months with their declaration folded in), `DeclareWireView` (the form + success state), `RentMonthRow` ("View proof", "Declare again"), `ProofPicker` (camera / photo library / Files, HEIC → JPEG; `ProofPickerRules` = `.wireProof` or `.issuePhoto`), `ProofViewer` (image or PDFKit sheet), `PayOnlineCard`. |
| `App/Features/Issues/` | `IssuesView` (Report button, "Open" / "Resolved" groups, `IssueRow`), `ReportIssueView` (category grid, description, photo grid, urgent toggle), `IssueDetailView` (header, report card, `IssueThreadRow` bubbles and status events, composer), `IssuePhotoViewer` (full-screen photo, thumbnails). |
| `App/Resources/InfoPlist.xcstrings` | Localized Info.plist strings (camera usage description). |
| `App/Resources/Localizable.xcstrings` | Every user-facing string, in `en` and `el`. Keys are identifiers (`home.rent.for`), not English text. |
| `Packages/TenantKit` | Swift package with everything testable outside the app. |
| `…/TenantCore` | `AppLanguage`, `L10n` (string lookup in the chosen language), lease / rent / issue values (`RentMonthStatus`, `WireDeclarationStatus`, `TenantIssueCategory`, `TenantIssueStatus`, `IssuePhotoRules`) and display formatting (`DD/MM/YYYY`, `DD/MM/YYYY HH:mm`, money, month labels, `YYYY-MM-DD`). Foundation only. |
| `…/TenantAPI` | `APIClient` (phone + code session, refresh, errors), Codable models (`TenantLease`, `TenantRent`, `TenantWireDeclaration`, `TenantIssue`, `TenantIssueDetail`…), endpoints, `MultipartForm` + `UploadFile` / `DownloadedFile` for the proof and photo uploads / downloads, Keychain token store. Foundation only. |

## Getting started (Mac)

```bash
brew install xcodegen
xcodegen generate
open KleidiTenant.xcodeproj
```

1. Set your team in `project.yml` (`DEVELOPMENT_TEAM`), or in Xcode under Signing.
2. Run the Kleidi server locally (`npm run dev` in the server repo, port 3000) with the
   `SMS_PROVIDER` app setting set to `console`: the login code is printed in the server log.
3. Link a tenant to a lease from the staff web app (lease card → Tenant app accounts).
4. Run the **KleidiTenant** scheme on a simulator; sign in with that tenant's phone number.

The simulator reaches `http://localhost:3000`. On a real device, open **Profile → Server**
(dev and stage builds only) and enter the Mac's LAN address.

Production is `https://kleidi.seamphony.io` (scheme **KleidiTenant Prod**). The stage URL in
`Config/Stage.xcconfig` is still a placeholder — set it before the first stage build.

## Tests

```bash
swift test --package-path Packages/TenantKit
```

TenantCore and TenantAPI build and test on Linux too, so `swift test` also runs in the Kleidi
server's dev container or a `swift:6.2` image. The SwiftUI app target needs Xcode.

## How the app talks to the server

- Every request sends `x-client: tenant-ios` and `x-client-build: <CFBundleVersion>`. No cookies, no CSRF.
- `POST /api/tenant/auth/request-code { phone }` then `POST /api/tenant/auth/verify-code { phone, code }`;
  the tokens come back in the body and are kept in the Keychain (`AfterFirstUnlockThisDeviceOnly`,
  service `app.kleidi.tenant.session`, one entry per server).
- Requests carry `Authorization: Bearer <access token>` (15 minutes). The client refreshes a minute
  before expiry, and once on a 401; concurrent callers share a single refresh because the server
  rotates the refresh token. `/tenant/auth/refresh` and `/tenant/auth/logout` take `{ refreshToken }` in the body.
- A rejected refresh ends the session (phone screen, with a reason when the number is no longer a tenant's).
- `GET /api/tenant/config` is checked at launch; a build below `ios.minSupportedBuild`, or any `426`
  response, shows the forced-update screen. Bump `CURRENT_PROJECT_VERSION` on every upload.
- Language: chosen on the first screen (pre-set from the device), stored on the phone, switchable in
  Profile without a restart. After sign-in the app `PATCH`es `/api/tenant/me { language }` once when the
  server's copy differs, and again on every change in Profile.

## Screens

- **Home** — "My lease": the rent card shows this month's amount and the newest month's real
  status pill (`GET /leases/:id/rent`; "Wire confirmed by property owner" when the month was paid
  through a confirmed declaration). "I paid by bank transfer" opens the Declare screen while any
  month can still be declared; otherwise the card says there is nothing to declare. Then the dashed
  "Pay online — COMING SOON" row, the lease terms and "Report an issue" (placeholder).
- **Payments** — the same declare button / nothing-to-declare line and the Pay-online row; a "Rent"
  card with every month (period, expected rent, status pill, "Paid / Declared / Due dd/mm/yyyy", and a
  red "Wire not confirmed — please contact management" note with management's remark when the last
  declaration on an unpaid month was rejected); a "Your declarations" card (months, amount, review
  status, "Declared dd/mm/yyyy", "View proof" → a sheet showing the image or the PDF, downloaded with
  the Bearer token).
- **Declare a bank transfer** — month multi-select (only declarable months, newest first, each with its
  expected rent), amount (decimal pad, prefilled with the selected months' rent until edited), transfer
  date (today or earlier), optional reference (140 chars), proof from the camera, the photo library or
  Files (PDF / JPG / PNG / WebP, 15 MB). Camera shots and HEIC / JPEG photos are re-encoded as JPEG
  (quality 0.85; downscaled to 2000 px on the longest side only if the JPEG would exceed 15 MB). Success
  shows "Wire declared" with buttons to Payments and back home; Home and Payments reload their months.
- **Issues** — the current lease's address, "Report an issue", then the issues in two groups:
  "Open" (received, in progress) and "Resolved" (resolved, closed). Each row: category icon tile
  (blue while open, red when urgent, grey once settled), summary, status pill (Received / In progress /
  Resolved / Closed), "Plumbing · reported dd/mm/yyyy" (or "resolved" / "closed" with that date), a red
  "Urgent" line while open, and a blue dot with "New reply from your property manager" when staff did
  something since the thread was last opened. Pull to refresh; the list reloads after a report, a reply
  or an opened thread.
- **Report an issue** — 3-column category grid (Plumbing / Electrical / Heating-AC / Doors-locks /
  Building / Other), multi-line description (2000 chars), "Photos (optional, up to 5)" grid with a dashed
  add tile (camera / photo library / Files; JPG, PNG, WebP, 10 MB each; HEIC and camera shots re-encoded as
  JPEG), the "It is urgent…" toggle and "Send to property manager". Success lands on the new issue's
  thread in the Issues tab (from Home the form is popped first).
- **Issue thread** — header (summary, "category · reported date", status pill; "Resolved on <date>" or
  "Closed by management · <reason>" once settled), the report card with its photo thumbnails (tap → full
  screen), "Received · dd/mm/yyyy HH:mm", then the thread: property-manager messages as white bubbles on
  the left ("Property manager · time"), the tenant's as accent bubbles on the right ("You · time"), status
  changes centred. While `canReply` the composer sends a text and / or up to 3 photos; otherwise the note
  "Once the issue is resolved, replies close. Still a problem? Report it again." with a link to the form.
  Opening the thread marks it seen on the server.
- **Profile** — unchanged.

## API contract

The Swift models mirror `server/types/tenantAuth.types.ts`, `server/types/tenantPortal.types.ts` and
`TenantWireDeclarationResponse` in `server/types/wireDeclarations.types.ts`. Only fields the app shows
are declared; unknown JSON keys are ignored and enum-like values (`status`, `paymentMethod`, `floor`,
the rent month and declaration statuses) decode as open string values, so a newer server does not
break an older app.

Phase 2 endpoints (all Bearer, `x-client: tenant-ios`):

| Call | Swift |
|------|-------|
| `GET /api/tenant/leases/:id/rent` → `{ leaseId, currencyCode, monthlyRent, paymentDayOfMonth, months[] }`, newest month first | `client.rent(leaseId:)` → `TenantRent` |
| `POST /api/tenant/leases/:id/wire-declarations` — `multipart/form-data`, text fields **before** the file: `periods` (JSON array), `declaredAmount`, `transferDate` (`YYYY-MM-DD`), `reference?`, then `proof` | `client.declareWire(leaseId:_:)` with a `WireDeclarationDraft` (`draft.form()` builds the body) |
| `GET /api/tenant/wire-declarations/:id/proof` → the file bytes (`Content-Type` image/* or application/pdf) | `client.wireProof(declarationId:)` → `WireProofFile` |

Errors: 400 `{ error, field }`, 404 lease, 409 a month already paid / declared, 413 proof too large,
415 unsupported type, 429 (5 declarations per 10 minutes) — all `APIError.http(status:…)`; the Declare
screen localizes 413 / 415 and shows the server's text for the rest.

Phase 3 endpoints (`server/types/tenantIssues.types.ts`; all Bearer):

| Call | Swift |
|------|-------|
| `GET /api/tenant/issues?leaseId=` → `{ data: TenantIssueOwnResponse[] }`, open first, then last activity desc | `client.issues(leaseId:)` → `[TenantIssue]` |
| `POST /api/tenant/leases/:id/issues` — `multipart/form-data`, text parts **first**: `category`, `description`, `isUrgent` (`true` / `false`), then 0–5 `photo` parts (jpeg / png / webp, ≤ 10 MB each) → 201 `TenantIssueOwnDetailResponse` | `client.reportIssue(leaseId:draft:photos:)` with a `ReportIssueDraft` (`draft.form(photos:)`) → `TenantIssueDetail` |
| `GET /api/tenant/issues/:id` → the issue fields + `messages[]` (tenant-visible, oldest first; marks the issue seen) | `client.issue(id:)` → `TenantIssueDetail` (`issue` + `messages`, decoded from the flat object) |
| `POST /api/tenant/issues/:id/messages` — multipart: `body` (only when there is text) then 0–3 `photo` parts → 201 `TenantIssueOwnMessageResponse`; 409 when resolved / closed | `client.replyToIssue(id:draft:photos:)` with an `IssueReplyDraft` → `TenantIssueMessage` |
| `GET /api/tenant/issues/:id/photos/:documentId` → the image bytes | `client.issuePhoto(issueId:documentId:)` → `DownloadedFile` |

Statuses are shown to the tenant as Received (`new`) / In progress / Resolved / Closed; `author` is
`tenant` or `staff` (always "Property manager", never a name). A `new` status event in `messages` is
not drawn — the report card's "Received · date" line already says it.
