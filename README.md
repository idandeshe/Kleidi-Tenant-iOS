# Kleidi Tenant iOS

Native SwiftUI app for **tenants** of properties managed with Kleidi: sign in with your phone
number and an SMS code, see your lease and this month's rent. Talks to the same Fastify server
as the staff app, through the tenant entrance `/api/tenant/*` (server repo: `docs/tenant-app.md`).
iOS 17+, iPhone only. Greek and English, chosen in the app.

Phase 1: language → phone + code sign-in → My lease (rent card, lease terms) → Profile.
Phase 2: rent months with their state, "I paid by bank transfer" (months, amount, date, proof
photo / PDF) and the declaration history on the Payments tab. Online payment and Issues are still
placeholders.

## Layout

| Path | What |
|------|------|
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated, never committed. |
| `Config/*.xcconfig` | Per-environment server URL, environment name and bundle id (Debug → dev `app.kleidi.tenant.dev`, Stage → `…stage`, Release → prod `app.kleidi.tenant`). |
| `App/` | The app target: `Shell/` (app model, root / tabs + `AppNavigation`, routes, theme, localization plumbing, server environment) and `Features/` (Language, Auth, Home, Payments, Profile, Placeholder). |
| `App/Features/Payments/` | `PaymentsView` (declare button, Pay-online placeholder, "Rent" months with their declaration folded in), `DeclareWireView` (the form + success state), `RentMonthRow` ("View proof", "Declare again"), `ProofPicker` (camera / photo library / Files, HEIC → JPEG), `ProofViewer` (image or PDFKit sheet), `PayOnlineCard`. |
| `App/Resources/InfoPlist.xcstrings` | Localized Info.plist strings (camera usage description). |
| `App/Resources/Localizable.xcstrings` | Every user-facing string, in `en` and `el`. Keys are identifiers (`home.rent.for`), not English text. |
| `Packages/TenantKit` | Swift package with everything testable outside the app. |
| `…/TenantCore` | `AppLanguage`, `L10n` (string lookup in the chosen language), lease / rent values (`RentMonthStatus`, `WireDeclarationStatus`) and display formatting (`DD/MM/YYYY`, money, month labels, `YYYY-MM-DD`). Foundation only. |
| `…/TenantAPI` | `APIClient` (phone + code session, refresh, errors), Codable models (`TenantLease`, `TenantRent`, `TenantWireDeclaration`…), endpoints, `MultipartForm` for the proof upload, Keychain token store. Foundation only. |

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
- **Issues** — still "Coming soon".
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
