# 13 — Risk Register

| Field | Value |
|-------|--------|
| Baseline | `refactor-split-main` @ `320f117` / tag `pre-full-audit` |
| Method | Static code audit + session automated checks; **no phone** attached |
| Cross-ref | Static findings **SC-001…SC-020**; architecture guide `12_`; automated report `06_` |
| Status legend | **Open** = unresolved at baseline; **Accepted/Fixed in tree** = behavior intentional or already corrected; **Watch** = monitor |

Severity: Critical / High / Medium / Low / Informational  
Confidence: Confirmed / Probable / Possible  

---

## Critical

| Risk ID | Severity | Confidence | Area | Description | Evidence | User impact | Data-loss possibility | Reproduction | Existing safeguard | Recommended future action | Phone verification needed | Status |
|---------|----------|------------|------|-------------|----------|-------------|------------------------|--------------|---------------------|---------------------------|---------------------------|--------|
| SC-005 | Critical (store / production distribution); High (internal APK trust) | Confirmed | Release / Android identity | Release builds use **debug signing**; `applicationId` / namespace remain **`com.example.showroom_scanner`**. | `android/app/build.gradle.kts` L9–10, L23–24, L34–38 (`signingConfig = signingConfigs.getByName("debug")`; TODO comments). Package path `com/example/showroom_scanner`. | Cannot publish meaningfully to Play; sideload update collisions; users may lose access to app-private data if applicationId later changes without migration. | **Yes** — changing applicationId later orphans `showroom_quotes/` unless migrated. | Inspect gradle; build `--release` and inspect cert. | Debug signing allows `flutter run --release` for local smoke. | Assign real applicationId + release keystore **before** any production install base; plan data migration if id must change. | No (config); Yes to validate sideload upgrade path | Open |

---

## High

| Risk ID | Severity | Confidence | Area | Description | Evidence | User impact | Data-loss possibility | Reproduction | Existing safeguard | Recommended future action | Phone verification needed | Status |
|---------|----------|------------|------|-------------|----------|-------------|------------------------|--------------|---------------------|---------------------------|---------------------------|--------|
| SC-001 | High | Confirmed | Maintainability | Monolithic `lib/main.dart` (~20,653 lines / ~19k code lines) owns UI, persistence, scan, pricing, import/export, archive. | File size; class outline (`ScannerHomePage`, models, export, archive, camera, ECatalog widgets). | Slow/safe change rate; regressions; hard reviews. | Indirect — higher chance of accidental persistence bugs when editing. | Open file; line count. | Partial split: `quote_bucket_routing.dart`, `master_products_sheet_builder.dart`; some Scan widgets extracted. | Incremental library extraction (see Architecture Guide §22); **not** a full rewrite. | No | Open |
| SC-002 | High | Confirmed | Error handling / persistence | Widespread silent `catch (_)` (~**46** in `main.dart`). | Ripgrep `catch\s*\(\s*_`; e.g. index parse L11165, email customer resolve L15986–15995, bucket config L6450. | Corrupt JSON / I/O failures fail quietly → stale UI, skipped archive moves, empty customer resolution. | **Yes** — bad rows skipped; failed ops may leave indexes inconsistent without user notice. | Corrupt `quote_*.json` or index entry; load/prune/email. | Some paths use `debugPrint` with `e` (e.g. persist working quote). | Log `e` at minimum; user-visible errors on persistence; reserve empty catch for true probes. | No (logic); optional Yes for UX | Open |
| SC-003 | High | Confirmed | Email / archive / UI | Load Quote dialog list **not refreshed** after email-archive; still shows archived rows until dialog closed. | `_LoadQuoteDialogContentState` copies `widget.allQuotes` in `initState` only; delete updates `_quotes`; email path `_onLoadQuoteEmailTapped` → archive without dialog list mutation; debug notes list not refreshed. | User may tap already-archived quote; confusion / failed load. | Low direct loss; **index confusion** / wrong expectations. | Open Load Quote → Email Current → cancel/dismiss share → row still listed. | Manual Remove; reopen dialog reloads from disk. | After archive, remove ids from dialog list or reload `_loadQuoteIndex()`; or close dialog. | **Yes** | Open |
| SC-004 | High | Confirmed | Email / archive | Share sheet open/return ≠ email sent; archive **not gated** on `ShareResultStatus`. | `_shareQuoteById` L16440–16497: logs `shareResult.status` but archives whenever `archiveAfterShare` after `Share.shareXFiles` returns; comment “archives after the share sheet opens”. Multi-share L16422–16429 same pattern. | Cancel share / non-email target still moves quote to Archive; false confidence email delivered. | **Yes** — active quote removed from Active workflow unexpectedly (file still on disk under archive). | Email Current → cancel share → check Archive / active index. | UI copy warns archive for Current/Customer; Email All is share-only. | Gate on success status (platform limits) + confirm; never equate sheet dismiss with delivery. | **Yes** | Open |
| SC-011 | High | Confirmed | Test / quality | Thin automated tests; placeholder widget test; no quote/scan/export/pricing/archive coverage. | `widget_test.dart` `expect(true, isTrue)`; only `summer_product_type_routing_test.dart` is real; session: **15 passed**. | Regressions caught only by manual phone passes. | Indirect. | `flutter test`. | Routing aliases covered; empty-starter comments in code. | Expand pure-helper unit tests; fake filesystem for indexes; later integration. | No | Open |

---

## Medium

| Risk ID | Severity | Confidence | Area | Description | Evidence | User impact | Data-loss possibility | Reproduction | Existing safeguard | Recommended future action | Phone verification needed | Status |
|---------|----------|------------|------|-------------|----------|-------------|------------------------|--------------|---------------------|---------------------------|---------------------------|--------|
| SC-006 | Medium | Confirmed | Diagnostics / privacy | Temporary diagnostics still enabled (`[QuoteDiag]`, `[EmailShare]`, `[EmailArchive]`, `[SummerRouteDiag]`, scanner focus spam). | Flags/comments “Temporary”; `_quoteDiag` always `debugPrint`; email/archive prints; focus listeners always print. | Log noise; PII (customer/quote ids) in logcat; perf cost. | No | Run app; create/load/email quote; filter logcat. | Some flags exist to silence subsets (`_scanPerfDebug`, rebuild instrument default false). | Single master `kDebugMode && flag` default **false**; strip stack dumps. | No | Open |
| SC-009 | Medium (case-sensitive FS); Low on Windows-only | Confirmed | Assets / packaging | Declared/loaded `products.csv`; Windows may display `Products.csv`; git tracks `products.csv`. | `pubspec.yaml` asset; `_loadProductsFromAssets` path; `git ls-files` → `products.csv`. | Asset-not-found on Linux CI / strict bundlers if casing diverges. | Catalog fallback fail → no scan. | Clone on Linux; cold start offline. | Web catalog preferred on startup. | Normalize casing with `git mv`; document. | No (CI); Yes if verifying Android asset fallback | Open / Watch |
| SC-010 | Medium | Confirmed | Tooling | `analysis_options.yaml` includes `flutter_lints` but package **missing** from `dev_dependencies`. | Include L10; `pubspec` only `flutter_test`; session `flutter analyze` → **1 issue** include not found. | No standard lints; analyze broken/noisy. | No | `flutter analyze` | None | Add `flutter_lints` **or** remove include. | No | Open |
| SC-012 | Medium | Confirmed | Routing | Dual bucket parse: runtime `_loadQuoteBucketConfig` vs tested `parseProductTypeBucketMappings`. | `main.dart` ~6402–6453; `quote_bucket_routing.dart` 27–67; parallel types `QuoteBucketDefinition` / `ProductTypeBucketMapping`. | Future JSON schema drift → tests green, app wrong (or reverse). | Wrong customer bucket / pricing context indirect. | Change JSON shape; compare loaders. | Summer aliases present in both JSON and seasonal set; unit tests on shared helper. | One parse → map to UI types. | No | Open |
| SC-013 | Medium | Confirmed | Startup / web-data | Always tries Google Sheets HTTP for products before assets. | `_loadProductsOnStartup` 9052–9068; `_productsCsvUrl` L48–49. | Slow/failed start on poor network; depends on sheet remaining public. | No (falls back to assets); **staleness** if fallback used. | Airplane mode cold start. | Asset fallback + audio init paths. | Prefer last-good cache; timeout; Setup-only refresh option. | **Yes** | Open |
| SC-014 | Medium | Confirmed | Ops / security posture | Hard-coded Sheet IDs/gids and public Netlify image host in source. | L48–52; image URLs ~12950, 18006, 18776, 18989, 19401. | URL rot; sheets must stay world-readable; no auth. | Catalog/image outage. | HTTP GET export URLs. | Bundled CSV/images fail soft. | Config/flavors; monitor link permissions. | No | Open |
| SC-015 | Medium | Probable | Persistence / lifecycle | Working lines often memory-only until routing/save/export/import/lifecycle pause. | Comments L4809–4812; `_persistWorkingQuoteIfAny` on paused/hidden only; force-stop not guaranteed. | Kill app mid-scan → lost lines. | **Yes** (unsaved workspace). | Force-stop after scans without pause/save. | Lifecycle persist; routing `_saveQuote`; Load Quote pre-save. | Debounced autosave after line mutations. | **Yes** | Open |
| SC-016 | Medium | Probable | Scanner / focus | Complex focus reclaim timers; races after dialogs/tabs/camera. | Multiple timers L4306–4311; listeners L4427–4443; Scan shrink off-tab comments. | Missed wedge scans after UI interruptions. | No | Load Quote / customer / camera → return → scan. | Dedupe window; serialized scan queue; suspend flag for catalog tests. | Simplify focus owner; gate debug prints. | **Yes** | Open |
| SC-017 | Medium | Probable | Performance | Full ~17.8k catalog in memory; ECatalog filters in Dart; large State `setState`. | products.csv line count; `_parseAndStoreProducts`; ECatalog build. | Jank on low-end phones; large-quote UI may stutter. | No | Profile ECatalog scroll; large quote panels. | CSV parse in isolate; startup delays. | Virtualization audit; isolate more work. | **Yes** | Open |
| SC-020 | Medium | Confirmed | Release readiness | App label `showroom_scanner`; example package namespace. | `AndroidManifest.xml` `android:label`; gradle `com.example.*`. | Unpolished identity; pairs with SC-005. | With id change: **Yes** (see SC-005). | Inspect manifest. | Functional app name in UI theme elsewhere. | Brand label + final applicationId with SC-005. | No | Open |

---

## Low

| Risk ID | Severity | Confidence | Area | Description | Evidence | User impact | Data-loss possibility | Reproduction | Existing safeguard | Recommended future action | Phone verification needed | Status |
|---------|----------|------------|------|-------------|----------|-------------|------------------------|--------------|---------------------|---------------------------|---------------------------|--------|
| SC-018 | Low | Confirmed | Logging | `print(...)` in product web load path (not `debugPrint`). | `_loadProductsFromWeb` ~9426, 9455, 9458. | Console noise in profiles. | No | Refresh products from web. | None | Gated `debugPrint`. | No | Open |
| SC-019 | Low | Confirmed | Master builder | Silent catch in mojibake repair loop. | `master_products_sheet_builder.dart` ~158–168 `catch (_) { break; }`. | Falls back to original text. | No | Odd encodings in source sheets. | Intentional decode attempts. | Optional debug counter; acceptable. | No | Accepted |
| SC-008 | Low / Informational (forward-compat) | Confirmed | Routing / ECatalog | Summer **SPRING/SUMMER** aliases in JSON + seasonal set; bundled CSV still mostly legacy `SUMMER *` labels. | JSON mappings; `kEcatalogSeasonalProductTypes`; tests; unique types in bundled CSV. | Live sheet labels route correctly when present; mismatch only if sheet uses unmapped strings. | Wrong bucket if unmapped type. | Unit tests; phone with live label. | Aliases + tests in tree. | Keep JSON+tests SoT; sync sheet types. | **Yes** if live catalog uses SPRING labels | Watch |

---

## Informational

| Risk ID | Severity | Confidence | Area | Description | Evidence | User impact | Data-loss possibility | Reproduction | Existing safeguard | Recommended future action | Phone verification needed | Status |
|---------|----------|------------|------|-------------|----------|-------------|------------------------|--------------|---------------------|---------------------------|---------------------------|--------|
| SC-007 | Informational (prior High bug fixed in tree) | Confirmed | Create Quote / routing | Empty-starter-only reuse: do **not** adopt non-empty saved quote when creating fresh workspace on same bucket. | `_ensureRoutingForProduct` ~6168–6205; `persistedQuoteDataIsEmptyForReuse`; reason `create_quote_safe_empty_starter_only`. | Prevents merging prior orders into empty Create Quote — **desired**. | N/A (prevents corruption). | Create Quote → scan with prior non-empty bucket quote on disk. | Explicit empty-only find + comments. | Keep; add regression tests. | **Yes** | Fixed in tree / verify on phone |

---

## Theme index (attention areas)

| Theme | Risk IDs |
|-------|----------|
| Data loss / quote corruption | SC-002, SC-004, SC-015, SC-005 (id change), SC-007 (mitigation) |
| Wrong customer / pricing / routing | SC-012, SC-008, SC-002 |
| Archive / email | SC-003, SC-004 |
| Index inconsistency | SC-002, SC-003, SC-004 |
| App update / identity | SC-005, SC-020 |
| Web-data dependency / local staleness | SC-013, SC-014, SC-009 |
| Scanner | SC-016 |
| Large catalog / large-quote performance | SC-017, SC-001 |
| Release readiness | SC-005, SC-010, SC-011, SC-020 |
| Maintainability / diagnostics | SC-001, SC-006, SC-018 |

---

## Counts (baseline register)

| Severity | Count |
|----------|-------|
| Critical | 1 (SC-005 dual-severity) |
| High | 5 |
| Medium | 10 |
| Low | 3 (incl. SC-008 dual) |
| Informational | 1 (SC-007) |
| **Total tracked** | **SC-001 … SC-020** |

Phone-heavy items (must not claim “fully verified” without device): **SC-003, SC-004, SC-007, SC-008 (live), SC-013, SC-015, SC-016, SC-017**.
