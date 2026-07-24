# 06 — Automated Test Report

| Field | Value |
|-------|--------|
| Baseline branch | `refactor-split-main` |
| Baseline commit | `320f117` — *Stable build before full application audit* |
| Full hash | `320f11780f76201ed1633e04024070a51b4f889d` |
| Tag | `pre-full-audit` |
| Audit date | 2026-07-23 |
| Scope | Read-only tooling / automated checks — **no production writes** |

---

## 1. Environment (`flutter doctor`)

| Item | Result |
|------|--------|
| Flutter | **3.41.9** (stable) |
| Dart | **3.11.5** |
| Android SDK | **36.1.0** |
| Java | **OpenJDK 21** |
| Connected devices | **Windows**, **Chrome**, **Edge** |
| Android phone | **None attached** |
| Visual Studio | **Not installed** (Windows desktop C++ toolchain incomplete for some desktop builds; not required for this report’s Dart tests) |

Phone / wedge-scanner / camera / share-sheet behaviors were **not** exercised by automated tests in this session.

---

## 2. Dependency resolve

| Command | Result |
|---------|--------|
| `flutter pub get` | Ran as part of analyze / test tooling |
| Lockfile | `git status` after checks showed **only** `?? docs/` — **no `pubspec.lock` change retained** |

---

## 3. Static analysis (`flutter analyze`)

| Metric | Result |
|--------|--------|
| Exit / issues | **1 issue** |
| Detail | `analysis_options.yaml` **include** `package:flutter_lints/flutter.yaml` **not found** |
| Root cause (static) | `flutter_lints` is **not** listed under `dev_dependencies` in `pubspec.yaml` (only `flutter_test`) — see **SC-010** |
| Production code changed | **No** |

---

## 4. Unit / widget tests (`flutter test`)

### 4a. Baseline product tests (pre-audit suites)

| Metric | Result |
|--------|--------|
| Outcome | **15 passed** |
| Failed | **0** |
| Suites | `test/summer_product_type_routing_test.dart` (14) + `test/widget_test.dart` (1 placeholder) |
| Coverage gaps | No automated coverage for quotes, persistence indexes, scan/focus, pricing totals, import/export, email/archive, ECatalog UI, camera, or master builder |

### 4b. Full run including investigation tests

| Metric | Result |
|--------|--------|
| Command | `flutter test test/audit test/summer_product_type_routing_test.dart test/widget_test.dart` |
| Outcome | **28 passed** |
| Failed | **0** |
| Breakdown | 13 audit + 14 summer routing + 1 placeholder |

### Pass interpretation

- Confirms JSON + `quote_bucket_routing.dart` helpers for **SUMMER** / **SPRING/SUMMER** aliases and seasonal chip membership.
- Does **not** prove end-to-end Create Quote, email archive, or scanner reliability on device.

---

## 5. Format check (read-only)

| Command | Result |
|---------|--------|
| `dart format --output=none --set-exit-if-changed lib test` | **Exit code 1** |
| Would change | `lib/master_products_sheet_builder.dart` |
| Write performed | **No** (`--output=none`; production untouched) |

Formatting drift is a hygiene finding only; not treated as a functional defect.

---

## 6. Investigation tests (`test/audit/`)

| Path | Result |
|------|--------|
| `test/audit/routing_audit_test.dart` | **13 passed** — normalization, Everyday/Summer/Halloween/Harvest/Mother's Day/St Patrick, unknown→null, category fallback, ECatalog seasonal |

### Testability limitations (no production refactor performed)

| Area | Why not fully testable without production changes |
|------|-----------------------------------------------------|
| Quote save/load/archive | Logic embedded in `_ScannerHomePageState` private methods; requires widget/integration harness or extraction |
| Email archive gating | Depends on `Share.shareXFiles` + dialog state; needs mocking / extraction |
| Pricing totals | Helpers private inside `main.dart` |
| MOQ / case rounding on add | Private `_addProduct` path |
| Import/export CSV builders | Coupled to UI + filesystem |
| Scanner focus / HID | Requires device + FocusNode lifecycle |
| Create Quote empty-starter policy | Inside `_ensureRoutingForProduct`; recommend extracting pure predicate for future unit tests |

Recommended future extraction (discussion only): persistence service, share/archive service, pricing pure functions, routing already partially extracted.

---

## 7. Commands summary (this session)

| Command | Outcome |
|---------|---------|
| `flutter doctor` | Environment recorded above |
| `flutter analyze` | 1 issue (missing `flutter_lints` package for include) |
| `flutter test` (product suites) | 15 passed |
| `flutter test` (+ `test/audit`) | 28 passed |
| `dart format --output=none --set-exit-if-changed lib test` | Exit 1; would reformat `master_products_sheet_builder.dart` only |
| Production files modified | **No** |
| Unexpected untracked outside docs/audit + test/audit | **No** |

---

## 8. Cross-references

| Finding | Related |
|---------|---------|
| SC-010 | Analyze include / missing `flutter_lints` |
| SC-011 | Thin tests (placeholder widget test) |
| SC-008 | Summer aliases covered by routing tests + audit suite |
| `12_Developer_Architecture_Guide.md` | Test architecture section |
| `13_Risk_Register.md` | Tooling / release / routing risks |
| `14_Full_App_Audit_Report.md` | Sections F–I (commands / tests) |
