# 14 — Full App Audit Report

| Field | Value |
|-------|--------|
| Product | Showroom Scanner |
| Baseline branch | `refactor-split-main` |
| Baseline commit | `320f117` — *Stable build before full application audit* |
| Full hash | `320f11780f76201ed1633e04024070a51b4f889d` |
| Tag | `pre-full-audit` |
| Audit date | 2026-07-23 |
| Constraint | **Documentation only** — production code not modified |
| Devices | Windows / Chrome / Edge; **no Android phone** |

Companion docs: `00_Audit_Session_Log.md`, `06_Automated_Test_Report.md`, `12_Developer_Architecture_Guide.md`, `13_Risk_Register.md` (plus earlier phase docs if present: `01`–`05`, `07`–`11`).

---

## A. Executive summary

Showroom Scanner is a Flutter quote/scanner app whose behavior is concentrated in a very large `lib/main.dart`, with two healthy extractions libraries (`quote_bucket_routing.dart`, `master_products_sheet_builder.dart`). Static review finds a **coherent domain model** (per–Product Type quote buckets, active/archive indexes, PS/NET/discount pricing, email/share + CSV export) and several **recent hardenings** (empty-starter Create Quote, Summer aliases, email archive wiring).

The highest user-facing risks at baseline are: **archive after share without delivery confirmation (SC-004)**, **stale Load Quote list after archive (SC-003)**, **silent error swallowing around persistence (SC-002)**, and **debug-signed `com.example` release identity (SC-005)**. Automated checks: **15 product tests passed**; **+13 investigation tests** under `test/audit/` (**28** when run together); **analyze** blocked by missing `flutter_lints`; format would touch only the master builder (not written). **Do not treat phone workflows as fully verified** — no device was attached.

A full rewrite is **not** justified; incremental modularization and targeted fixes are.

---

## B. Audit scope

**In scope**

- Static review of `lib/`, `assets/data/`, `test/`, `pubspec.yaml`, `analysis_options.yaml`, Android manifests/gradle
- Architecture, risks, automated tooling results
- Cross-check of findings SC-001…SC-020

**Out of scope / not performed**

- Production code changes, commits, branch switches
- Physical phone: wedge scan, camera, share targets, real email, OneDrive/Documents paths on device
- Live Google Sheet content mutation
- Performance profiling on hardware
- Security penetration beyond static config review

---

## C. Baseline commit and tag

| Check | Result |
|-------|--------|
| Branch | `refactor-split-main` |
| HEAD | `320f11780f76201ed1633e04024070a51b4f889d` |
| Message | Stable build before full application audit |
| Tag at HEAD | `pre-full-audit` |
| Pre-docs working tree | Clean (docs/` then appear as untracked) |

---

## D. Files reviewed

| Path | Notes |
|------|-------|
| `lib/main.dart` | Primary (~20k lines) — searched + key sections read |
| `lib/quote_bucket_routing.dart` | Full |
| `lib/master_products_sheet_builder.dart` | Header/API + silent-catch site |
| `pubspec.yaml` / `analysis_options.yaml` | Full |
| `assets/data/*` | products/customers/walk-order/buckets JSON |
| `test/*.dart` | Full |
| `android/app/build.gradle.kts` | Signing / applicationId |
| `android/app/src/main/AndroidManifest.xml` | Permissions / label |
| `README.md` | Stock Flutter template (not product docs) |

---

## E. Features inventoried

| ID | Feature |
|----|---------|
| F-01 | Startup / cold start (customers → web products → asset fallback → prune → focus) |
| F-02 | Customers (CSV + local added; discount %) |
| F-03 | Quotes create/load/save/name; empty-starter reuse |
| F-04 | Product Type buckets + Summer aliases |
| F-05 | Scanning (wedge, quick entry, camera) |
| F-06 | Order lines (qty, edit, dismiss) |
| F-07 | Pricing (PS > NET > discount > regular) |
| F-08 | Product info / search |
| F-09 | E-Catalog (chips, seasonal, images) |
| F-10 | Import order CSV |
| F-11 | Export / email share (CSV+XLSX+text) |
| F-12 | Archive / confirmed |
| F-13 | Setup (refresh, walk order, master build, catalog tests) |

---

## F. Commands run

| Command | Purpose |
|---------|---------|
| `git status` / `git log` / `git rev-parse` / tag points-at | Baseline safety |
| `flutter doctor` | Environment |
| `flutter pub get` | Resolve (via analyze/test) |
| `flutter analyze` | Static analysis |
| `flutter test` | Unit/widget tests |
| `dart format --output=none --set-exit-if-changed lib test` | Format drift check (**no write**) |
| Ripgrep / file reads | Static evidence for SC-* |

---

## G. Tests run

- `flutter test` (default suite under `test/`) — 15 tests
- `flutter test test/audit …` — includes `test/audit/routing_audit_test.dart` (13) → **28 total** when combined

---

## H. Tests passed

- **15** product suite tests
  - Summer / seasonal / everyday routing + ECatalog seasonal membership (`summer_product_type_routing_test.dart`)
  - Placeholder widget test (`widget_test.dart`)
- **13** investigation tests (`test/audit/routing_audit_test.dart`)
- **28** combined; **0** failures

---

## I. Tests failed

- **0** test failures
- **Related non-test failures**
  - `flutter analyze`: **1 issue** — `flutter_lints` include not found (**SC-010**)
  - `dart format --output=none --set-exit-if-changed`: **exit 1** — would change `lib/master_products_sheet_builder.dart` (no write)

---

## J. Features verified by code

| Feature | Verification level |
|---------|-------------------|
| Entry + portrait + theme shell | Code |
| Bucket JSON load + Summer alias maps | Code + unit tests |
| Empty-starter-only Create Quote reuse | Code (SC-007) |
| Pricing precedence PS>NET>discount | Code |
| Quote dirs / active+archive indexes / legacy migrate | Code |
| Email Current/Customer archive-after-share wiring | Code (SC-004 caveat) |
| Export-success archive path | Code |
| Lifecycle persist on pause/hidden | Code (SC-015 caveat) |
| Image URL pattern | Code |
| Debug release signing / com.example | Code (SC-005) |
| Hard-coded Sheet URLs | Code (SC-014) |

---

## K. Features verified by tests

| Feature | Tests |
|---------|-------|
| `SPRING/SUMMER` → summer buckets | Yes |
| Legacy `SUMMER *` buckets | Yes |
| Seasonal chip membership set | Yes |
| Unchanged Halloween/Harvest/Mother’s/Everyday routing | Yes |
| Everything else (quotes, scan, email, pricing totals, import) | **No** |

---

## L. Features requiring phone verification

- Wedge scanner reliability after dialogs/tabs/camera (**SC-016**)
- Camera scan path
- Share sheet cancel vs archive (**SC-004**)
- Load Quote list staleness after email archive (**SC-003**)
- Create Quote empty-starter with real prior quotes (**SC-007**)
- Airplane-mode / poor-network cold start (**SC-013**)
- Force-kill persistence gaps (**SC-015**)
- ECatalog scroll jank / large quotes (**SC-017**)
- Live Sheet Product Types using SPRING labels (**SC-008**)
- Android Documents / `Showroom_Sync` export paths
- Actual email client delivery (never claim from share API alone)

---

## M. Critical findings

1. **SC-005** — Release signed with debug keys; `com.example.showroom_scanner` applicationId. Blocks trustworthy production distribution; applicationId change later risks orphaning local quotes.

---

## N. High findings

1. **SC-001** — Monolithic `main.dart` (~20k lines).
2. **SC-002** — Silent `catch (_)` (~46 sites) around persistence/UI helpers.
3. **SC-003** — Load Quote list stale after email archive.
4. **SC-004** — Archive not gated on share success / not proof of email sent.
5. **SC-011** — Thin tests; regressions rely on manual phone.

---

## O. Medium findings

- **SC-006** Temporary diagnostics enabled / noisy / PII in logs  
- **SC-009** products.csv casing risk on case-sensitive systems  
- **SC-010** Missing `flutter_lints` vs analysis_options include  
- **SC-012** Dual bucket parse paths (drift risk)  
- **SC-013** Startup always hits network first  
- **SC-014** Hard-coded Sheet/image URLs  
- **SC-015** Lifecycle persist gaps / force-kill  
- **SC-016** Scanner focus race complexity  
- **SC-017** Large catalog performance risk  
- **SC-020** Unbranded Android label / example package  

---

## P. Low findings

- **SC-018** `print` in web product load  
- **SC-019** Master builder mojibake silent catch (acceptable)  
- **SC-008** Summer aliases present (forward-compat; verify live sheet)  

---

## Q. Informational findings

- **SC-007** Empty-starter Create Quote fix **present** in tree — keep and regression-test; phone-confirm  
- Format drift on `master_products_sheet_builder.dart` (hygiene only)  
- Orders tab code retained but hidden from navigation  
- README still stock Flutter template  

---

## R. Data-loss risks

| Risk | Notes |
|------|-------|
| Unsaved workspace on kill | SC-015 |
| Unexpected archive after cancelled share | SC-004 (active workflow loss; files move to archive index) |
| Silent skip of corrupt index/quote rows | SC-002 |
| applicationId change without migration | SC-005 |
| Mitigated: empty-starter no longer merges non-empty quotes | SC-007 |

---

## S. Pricing risks

- Precedence implemented clearly in code; **no automated total tests**.
- Customer discount parsing has careful 0–1 vs percent rules — edge cases need phone/sample CSV checks.
- Share/export rebuild pricing from persisted flags — corruption/`catch` paths could omit lines quietly (**SC-002**).
- **Confidence: Moderate** (see ratings).

---

## T. Routing risks

- Dual parsers (**SC-012**).
- Unmapped Product Types fall through Pride/Everyday heuristics — wrong bucket possible.
- Summer aliases covered by tests (**SC-008**); live Sheet must stay mapped.
- Empty-starter rules critical for Create Quote (**SC-007**).

---

## U. Persistence risks

- Split indexes + legacy migration — generally solid design; silent catches weaken trust (**SC-002**).
- Email archive vs dialog list (**SC-003**).
- Memory-only lines until save triggers (**SC-015**).
- App update keeps on-device quotes; asset catalog may refresh independently (staleness).

---

## V. Performance risks

- ~17.8k products in RAM; ECatalog filtering; monolith `setState` (**SC-017**, **SC-001**).
- Startup web download on every cold start (**SC-013**).
- Diagnostic spam (**SC-006**) adds overhead in debug.

---

## W. Security / privacy risks

- CAMERA + INTERNET permissions appropriate for features.
- Public Sheet export URLs (no auth) — data visibility is an ops choice (**SC-014**).
- Debug signing / example package (**SC-005**).
- Logs may contain customer/quote identifiers (**SC-006**).
- No evidence of intentional exfiltration beyond configured Sheet/image hosts.

---

## X. Release-readiness assessment

| Gate | Status |
|------|--------|
| Unique applicationId | **Fail** (`com.example`) |
| Release signing | **Fail** (debug keys) |
| Analyzer / lints | **Fail** (missing flutter_lints) |
| Automated regression breadth | **Fail** (thin tests) |
| Core quoting/scan code coherence | **Pass with caveats** |
| Phone QA matrix | **Not run** |
| Store listing polish (label) | **Weak** |

**Verdict:** Suitable for **continued internal development / controlled sideload experimentation**, **not** ready for production/store release without SC-005/SC-020 and high email-archive fixes plus a real device QA pass.

---

## Y. Documentation created (this audit set)

| Doc | Topic |
|-----|-------|
| `00_Audit_Session_Log.md` | Phase 0 / session |
| `06_Automated_Test_Report.md` | Doctor / analyze / test / format |
| `12_Developer_Architecture_Guide.md` | Architecture |
| `13_Risk_Register.md` | SC-001…SC-020 register |
| `14_Full_App_Audit_Report.md` | This report (A–Z) |

*(Other numbered phase docs `01`–`05`, `07`–`11` may be authored in parallel sessions.)*

---

## Z. Recommended discussion order

1. **SC-005 / SC-020** — applicationId + signing (decide before more production installs)  
2. **SC-004** — archive gating vs share result / user confirm  
3. **SC-003** — Load Quote UI refresh after archive  
4. **SC-015** — autosave policy  
5. **SC-002** — stop silent catches on persistence paths  
6. **SC-010 / SC-011** — lints + expand unit tests (routing already started)  
7. **SC-012** — unify bucket parse  
8. **SC-013 / SC-014** — startup/cache/config for Sheets  
9. **SC-016 / SC-017** — scanner focus + ECatalog perf (phone-led)  
10. **SC-001 / SC-006** — incremental modularization + diag cleanup (not rewrite)  

---

## Overall confidence ratings

| Area | Rating | Explanation |
|------|--------|-------------|
| **Code correctness** | **Moderate** | Core flows are readable and often carefully commented; silent catches, dual parsers, and thin tests prevent High. No phone confirmation of scan/share. |
| **Quote persistence** | **Moderate** | Split indexes, migration, prune, empty-starter, lifecycle persist show deliberate design; SC-002/SC-015/SC-003/SC-004 keep residual loss/corruption/UX risks. |
| **Scanner reliability** | **Low** | Complex focus machine; no device/wedge/camera verification this session (**SC-016**). |
| **Pricing** | **Moderate** | Clear precedence and rounding helpers in code; **no** total/regression tests; needs sample-matrix phone check. |
| **Routing** | **High** | JSON aliases + shared helpers covered by **passing** unit tests; residual dual-parse drift (**SC-012**) and live Sheet sync. |
| **Import/export** | **Moderate** | Substantial code paths for CSV import/export and `Showroom_Sync` layout; not exercised automatically; export-archive vs share-archive differ. |
| **Email/archive** | **Low–Moderate** | Wiring for archive-after-email exists (improved vs “never archives”), but **SC-004** + **SC-003** are Confirmed High; no phone share-target matrix. Rated **Low** for “safe to rely on in showroom,” **Moderate** for “code path exists.” → use **Low** for operational trust until phone QA. |
| **ECatalog** | **Moderate** | Feature-complete in code (chips, seasonal set, images); performance and image host unproven on phone (**SC-017**, **SC-014**). |
| **Release readiness** | **Low** | Debug signing, example applicationId, analyze broken, thin tests, no phone QA (**SC-005**, **SC-010**, **SC-011**, **SC-020**). |

### Email/archive rating clarification

For the summary table above, **email/archive = Low** (do not claim production-safe until SC-003/SC-004 phone-verified and gating improved). Static understanding of the intended Current/Customer/All menu behavior is Moderate.

---

*End of Full App Audit Report — baseline `320f117` / `pre-full-audit`.*
