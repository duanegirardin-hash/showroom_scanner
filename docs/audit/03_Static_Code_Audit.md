# 03 — Static Code Audit

| Field | Value |
|-------|--------|
| Baseline | `320f117` / `pre-full-audit` |
| Method | Static reading of Dart / Android / assets / tests at HEAD |
| Production change | **No** |

Severity: Critical / High / Medium / Low / Informational  
Confidence: Confirmed / Probable / Possible  

---

## SC-001 — Monolithic `main.dart` (~20k lines)

| Field | Value |
|-------|--------|
| Severity | High |
| Confidence | Confirmed |
| File | `lib/main.dart` |
| Scope | Entire compilation unit (~20,653 lines) |
| Evidence | File contains UI, persistence, import/export, pricing, scanning, archive, setup |
| Likely user impact | Indirect — slow fixes, high regression risk |
| Reproduction idea | Open file; measure line count |
| Recommended future action | Continue modular split (routing already extracted); peel persistence, scan, ECatalog, export |
| Phone verification required | No |
| Production change made | No |

---

## SC-002 — Widespread silent `catch (_)`

| Field | Value |
|-------|--------|
| Severity | High |
| Confidence | Confirmed |
| File | `lib/main.dart` (+ one in `master_products_sheet_builder.dart`) |
| Scope | Quote index parse, prune, email context, CSV probes, etc. (~46 matches in `main.dart`) |
| Evidence | Examples at lines ~1880, 5162, 5786, 5803, 5843, 5928, 6038, 6819, 15986–15995, 16167 |
| Likely user impact | Corrupt quote / I/O failure fails silently → stale UI or missing archive moves |
| Reproduction idea | Corrupt a `quote_*.json` then load/prune |
| Recommended future action | Log errors; surface user-facing messages on persistence paths |
| Phone verification required | No (logic); optional Yes for UX |
| Production change made | No |

---

## SC-003 — Load Quote dialog list may not refresh after email archive

| Field | Value |
|-------|--------|
| Severity | High |
| Confidence | Confirmed |
| File | `lib/main.dart` |
| Function | `_LoadQuoteDialogContentState`; `_archiveActiveQuotesAfterEmailShare`; `_onLoadQuoteEmailTapped` |
| Evidence | `_quotes = List.from(widget.allQuotes)` only in `initState`; delete path updates `_quotes`; email-archive path does not; comments note dialog list is NOT refreshed |
| Likely user impact | After Email Current/Customer, archived quotes can still appear in open dialog |
| Reproduction idea | Open Load Quote → Email Current → cancel/dismiss share → row still listed |
| Recommended future action | Refresh dialog list from index after archive; or close/rebuild dialog |
| Phone verification required | Yes |
| Production change made | No |

---

## SC-004 — Share sheet success ≠ email sent; archive not gated on share status

| Field | Value |
|-------|--------|
| Severity | High |
| Confidence | Confirmed |
| File | `lib/main.dart` |
| Function | `_shareQuoteById`, `_shareMultipleSavedQuotesForEmail` |
| Evidence | Comment: archives after share sheet opens; `shareResult.status` logged but not branched on for archive gate |
| Likely user impact | Cancel share / pick non-email target → quote still archived |
| Reproduction idea | Email Current → cancel share sheet → check Archive vs Active |
| Recommended future action | Gate archive on success status where platform allows; confirm dialog; never equate sheet dismiss with delivery |
| Phone verification required | Yes |
| Production change made | No |

---

## SC-005 — Release signed with debug keys / `com.example` applicationId

| Field | Value |
|-------|--------|
| Severity | Critical (store/production distribution) |
| Confidence | Confirmed |
| File | `android/app/build.gradle.kts` |
| Line range | ~9–10, 23–24, 34–38 |
| Evidence | `applicationId = "com.example.showroom_scanner"`; `signingConfig = signingConfigs.getByName("debug")` |
| Likely user impact | Cannot publish meaningfully; update identity conflicts; trust mismatch |
| Recommended future action | Real applicationId + release keystore before production install base |
| Phone verification required | No (config); Yes for sideload validation |
| Production change made | No |

---

## SC-006 — Temporary diagnostics left enabled

| Field | Value |
|-------|--------|
| Severity | Medium |
| Confidence | Confirmed |
| File | `lib/main.dart` |
| Evidence | `[QuoteDiag]`, `[EmailShare]`, `[EmailArchive]`, `[SummerRouteDiag]`; stack dumps on some load paths |
| Likely user impact | Log noise; possible customer/quote id exposure in logcat; minor performance |
| Recommended future action | Gate behind `kDebugMode && flag` default false; remove stack dump on load |
| Phone verification required | No |
| Production change made | No |

---

## SC-007 — Create Quote empty-starter-only reuse (baseline fix present)

| Field | Value |
|-------|--------|
| Severity | Informational (fix confirmed) |
| Confidence | Confirmed |
| File | `lib/main.dart` |
| Function | `_ensureRoutingForProduct` |
| Evidence | `reason=create_quote_safe_empty_starter_only` — only empty starter adopted when `_currentQuoteId == null` on target bucket |
| Likely user impact | Prevents huge prior / FULL CATALOG quotes from flooding Create Quote workspace — **desired** |
| Recommended future action | Keep; add regression test around empty-reuse helpers |
| Phone verification required | Yes |
| Production change made | No |

---

## SC-008 — Summer SPRING/SUMMER aliases in JSON + ECatalog set

| Field | Value |
|-------|--------|
| Severity | Informational / Low |
| Confidence | Confirmed |
| File | `assets/data/product_type_buckets.json`; `lib/quote_bucket_routing.dart` |
| Evidence | SPRING/SUMMER - GENERAL/TOYS → summer_general / summer_toys; tests assert; ECatalog seasonal includes both naming schemes |
| Likely user impact | Live sheet labels route correctly when present |
| Phone verification required | Yes if live catalog uses SPRING labels |
| Production change made | No |

---

## SC-009 — Asset casing `products.csv` vs `Products.csv`

| Field | Value |
|-------|--------|
| Severity | Medium (case-sensitive platforms) |
| Confidence | Confirmed |
| File | `pubspec.yaml`; `lib/main.dart` `_loadProductsFromAssets`; `assets/data/` |
| Evidence | Declared/loaded `assets/data/products.csv`; Windows may display `Products.csv` |
| Likely user impact | Possible asset-not-found on Linux CI / strict bundlers |
| Recommended future action | Normalize casing in git to match pubspec |
| Phone verification required | No (CI); Android fallback path optional Yes |
| Production change made | No |

---

## SC-010 — `flutter_lints` include without dependency

| Field | Value |
|-------|--------|
| Severity | Medium |
| Confidence | Confirmed |
| File | `analysis_options.yaml`; `pubspec.yaml` |
| Evidence | `flutter analyze` reports include_file_not_found for `package:flutter_lints/flutter.yaml` |
| Likely user impact | Weak static analysis; tooling noise |
| Recommended future action | Add `flutter_lints` **or** remove include |
| Phone verification required | No |
| Production change made | No |

---

## SC-011 — Thin automated tests

| Field | Value |
|-------|--------|
| Severity | High (quality risk) |
| Confidence | Confirmed |
| File | `test/widget_test.dart`; `test/summer_product_type_routing_test.dart` |
| Evidence | 15 tests total pre-audit expansion; widget_test is placeholder; no quote/scan/export/pricing tests |
| Likely user impact | Regressions rely on manual phone passes |
| Recommended future action | Expand unit tests for pure helpers; integration for index transitions |
| Phone verification required | No |
| Production change made | No |

---

## SC-012 — Duplicate bucket model / dual JSON parse paths

| Field | Value |
|-------|--------|
| Severity | Medium |
| Confidence | Confirmed |
| File | `lib/main.dart`, `lib/quote_bucket_routing.dart` |
| Evidence | `QuoteBucketDefinition` parallel to `ProductTypeBucketMapping`; runtime maps filled by separate parser |
| Likely user impact | Drift risk between tested helpers and runtime loader |
| Recommended future action | Single parse → map into UI types |
| Phone verification required | No |
| Production change made | No |

---

## SC-013 — Startup always tries network for products

| Field | Value |
|-------|--------|
| Severity | Medium |
| Confidence | Confirmed |
| File | `lib/main.dart` |
| Function | `_loadProductsOnStartup` → `_loadProductsFromWeb` |
| Evidence | HTTP Google Sheets export before assets; fallback on failure |
| Likely user impact | Slow/failed start on poor network (still falls back) |
| Recommended future action | Prefer cached last-good; Setup-only refresh option |
| Phone verification required | Yes |
| Production change made | No |

---

## SC-014 — Hard-coded Sheet IDs and public image host

| Field | Value |
|-------|--------|
| Severity | Medium |
| Confidence | Confirmed |
| File | `lib/main.dart` |
| Evidence | `_productsCsvUrl`, `_customersCsvUrl`; `showroom-images.netlify.app` |
| Likely user impact | URL rot; sheets must stay world-readable; no auth |
| Recommended future action | Config/flavor; monitor link permissions |
| Phone verification required | No |
| Production change made | No |

---

## SC-015 — Lifecycle persistence gaps (probable)

| Field | Value |
|-------|--------|
| Severity | Medium |
| Confidence | Probable |
| File | `lib/main.dart` |
| Function | `didChangeAppLifecycleState` → `_persistWorkingQuoteIfAny` |
| Evidence | Persists on paused/hidden; not on every line add |
| Likely user impact | Force-stop mid-scan may lose unsaved lines |
| Recommended future action | Debounced autosave after line mutations |
| Phone verification required | Yes |
| Production change made | No |

---

## SC-016 — Scanner focus complexity / race risk

| Field | Value |
|-------|--------|
| Severity | Medium |
| Confidence | Probable |
| File | `lib/main.dart` |
| Evidence | Multiple refocus timers; Scan subtree not built off-tab; extensive focus debug |
| Likely user impact | Missed wedge scans after dialogs / tab switches |
| Recommended future action | Simplify focus owner; gate debug |
| Phone verification required | Yes |
| Production change made | No |

---

## SC-017 — Large catalog performance (probable)

| Field | Value |
|-------|--------|
| Severity | Medium |
| Confidence | Probable |
| File | `lib/main.dart`; products CSV ~17.8k rows |
| Evidence | Full catalog maps; E-Catalog filters in Dart; monolith setState |
| Likely user impact | Jank on low-end phones |
| Recommended future action | Profile E-Catalog; isolate patterns |
| Phone verification required | Yes |
| Production change made | No |

---

## SC-018 — `print` in product web load path

| Field | Value |
|-------|--------|
| Severity | Low |
| Confidence | Confirmed |
| File | `lib/main.dart` |
| Function | `_loadProductsFromWeb` |
| Evidence | Uses `print(...)` not `debugPrint` |
| Recommended future action | Gated `debugPrint` |
| Phone verification required | No |
| Production change made | No |

---

## SC-019 — Master builder mojibake silent catch

| Field | Value |
|-------|--------|
| Severity | Low |
| Confidence | Confirmed |
| File | `lib/master_products_sheet_builder.dart` |
| Evidence | Intentional `catch (_) { break; }` in decode attempts |
| Impact | Low — falls back to original text |
| Phone verification required | No |
| Production change made | No |

---

## SC-020 — App label / example package identity

| Field | Value |
|-------|--------|
| Severity | Medium |
| Confidence | Confirmed |
| File | AndroidManifest + gradle |
| Evidence | `android:label="showroom_scanner"`; `com.example.*` |
| Recommended future action | Brand label + final applicationId with SC-005 |
| Phone verification required | No |
| Production change made | No |

---

## Theme coverage map

| Theme | Findings |
|-------|----------|
| Correctness | SC-003, SC-004, SC-007, SC-008, SC-012 |
| Persistence / data loss | SC-002, SC-015 |
| Async / lifecycle | SC-015, SC-016 |
| Scanner / input | SC-016 |
| Pricing | No confirmed defect ID without phone (logic appears PS>NET>discount) |
| Data loading | SC-009, SC-013, SC-014 |
| Performance | SC-001, SC-017 |
| Error handling | SC-002, SC-018 |
| Maintainability | SC-001, SC-006, SC-010, SC-011, SC-012 |
| Security / privacy | SC-005, SC-006, SC-014 |
| Release readiness | SC-005, SC-020 |

**No production changes made.**
