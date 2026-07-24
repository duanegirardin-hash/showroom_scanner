# 01 — Repository Inventory

| Field | Value |
|-------|--------|
| Baseline branch | `refactor-split-main` |
| Baseline commit | `320f117` — Stable build before full application audit |
| Full hash | `320f11780f76201ed1633e04024070a51b4f889d` |
| Tag | `pre-full-audit` |
| Audit date | 2026-07-23 |
| Scope | Read-only static inventory |

---

## 1. Summary

| Area | Count / notes |
|------|----------------|
| Dart lib | 3 files; dominated by `lib/main.dart` (~20,653 lines) |
| Tests (pre-audit) | 2 files: summer routing suite + placeholder widget test |
| Bundled data | 4 under `assets/data/` |
| Sounds | 3 MP3 |
| Android | manifests + Gradle Kotlin; package `com.example.showroom_scanner` |
| Scripts | None in repo root |
| Leftover | `scanner_test/` IDE/gradle stubs (not app source) |

---

## 2. Dart library files

### 2.1 `lib/main.dart`

| Attribute | Detail |
|-----------|--------|
| Purpose | Entire showroom scanner UI + business logic monolith |
| Size | ~20,653 lines |
| Status | **Current** — maintainability / coupling hub |
| Business logic | Yes |
| Persistent data | Yes (`showroom_quotes/`, `added_customers.json`, exports) |
| Diagnostics | Yes — `[QuoteDiag]`, `[EmailShare]`, `[EmailArchive]`, `[SummerRouteDiag]`, `[MasterBuildDiag]`, `[WhseDiag]`, focus/scan logs |
| Test coverage | Almost none directly |

**Key symbols:** `main()`, `ShowroomScannerApp`, `Product`, `Customer`, `OrderLine`, `SavedQuoteInfo`, `ScannerHomePage` / `_ScannerHomePageState`, `_LoadQuoteDialogContent`, `_SetupTab`, `_ArchiveQuotesTab`, `_CameraScannerPage`, `_OrderListTab` (Orders tab hidden), `_ECatalog*` widgets, import/export helpers.

**Dependencies:** Flutter; `audioplayers`, `csv`, `excel`, `file_picker`, `http`, `mobile_scanner`, `path`, `path_provider`, `share_plus`; local `quote_bucket_routing.dart`, `master_products_sheet_builder.dart`.

**Runtime:** Always (app entry).

### 2.2 `lib/quote_bucket_routing.dart`

| Attribute | Detail |
|-----------|--------|
| Purpose | Side-effect-free Product Type → bucket normalization + ECatalog seasonal membership |
| Status | **Current** (shared + tested) |
| Business logic | Yes |
| Persistent data | No |
| Diagnostics | No |
| Test coverage | **Yes** — `test/summer_product_type_routing_test.dart` |

**API:** `normalizeBucketLookupKey`, `ProductTypeBucketMapping`, `parseProductTypeBucketMappings`, `lookupProductTypeBucketMapping`, `kEcatalogSeasonalProductTypes`, `isEcatalogSeasonalProductType`.

**Note:** `main.dart` still maintains parallel `QuoteBucketDefinition` maps loaded separately — partial duplication.

### 2.3 `lib/master_products_sheet_builder.dart`

| Attribute | Detail |
|-----------|--------|
| Purpose | Setup debug “Build Updated Master Products Sheet” Excel merge |
| Status | **Current** (debug Setup flow) |
| Business logic | Yes (spreadsheet ops) |
| Test coverage | None |
| Diagnostics | `[MasterBuildDiag]`, `[WhseDiag]` |

**API:** `runUpdatedMasterProductsBuild(...)` → `MasterProductsBuildReport`.

---

## 3. Tests

| Path | Purpose | Status |
|------|---------|--------|
| `test/summer_product_type_routing_test.dart` | Summer/SPRING aliases, seasonal chip, sample seasonals | **Current** |
| `test/widget_test.dart` | Placeholder `expect(true, isTrue)` | **Stub** |
| `test/audit/` | Investigation-only tests created by this audit | **Audit only** |

**Gap:** No automated tests for scan, save/load quotes, archive, email share, pricing, import/export, CSV parse, master builder, or `ScannerHomePage` smoke.

---

## 4. Assets

### 4.1 Data

| Path | Purpose | Runtime | Status | Notes |
|------|---------|---------|--------|-------|
| `assets/data/products.csv` (Windows may show `Products.csv`) | Catalog fallback | `rootBundle.loadString('assets/data/products.csv')` | Current + **casing risk** | ~17.8k rows; ~2.9 MB |
| `assets/data/customers.csv` | Customers seed | Startup | Current | ~257 rows |
| `assets/data/customer_walk_order.csv` | Walk order / NeverAdd | Startup + Walk Order Editor | Current | ~1.8k rows |
| `assets/data/product_type_buckets.json` | Raw Product Type → bucketKey/displayLabel | `_loadQuoteBucketConfig` | Current | Includes SPRING/SUMMER aliases |

**Casing:** `pubspec.yaml` and git track `products.csv`; Windows Explorer may show `Products.csv`. Risk on case-sensitive hosts.

### 4.2 Sounds

| Path | Use |
|------|-----|
| `assets/sounds/good_scan.mp3` | Success |
| `assets/sounds/good_scan2.mp3` | Alternate success |
| `assets/sounds/error_scan.mp3` | Error / not found |

All declared in `pubspec.yaml` and referenced in code.

---

## 5. Package / config

| Path | Notes |
|------|-------|
| `pubspec.yaml` | `showroom_scanner` 1.0.0+1; SDK `>=3.10.3 <4.0.0`; assets listed; **no `flutter_lints` package** |
| `pubspec.lock` | Locked deps |
| `analysis_options.yaml` | Includes `package:flutter_lints/flutter.yaml` but dependency missing → analyze warning |
| `README.md` | Flutter starter boilerplate (not product docs) |

---

## 6. Android

| Path | Notes |
|------|-------|
| `AndroidManifest.xml` (main) | CAMERA, INTERNET, WRITE_EXTERNAL_STORAGE maxSdk 28; label `showroom_scanner` |
| `android/app/build.gradle.kts` | `applicationId`/`namespace` = `com.example.showroom_scanner`; **release signed with debug** |
| `MainActivity.kt` | Method channel `com.example.showroom_scanner/documents` for public CSV export |
| Debug/profile manifests | INTERNET for tooling |

---

## 7. Other / uncertain

| Path | Assessment |
|------|------------|
| `scanner_test/` | Unused leftover |
| Orders tab UI in `main.dart` | Dormant — hidden from TabBar (`_visibleTabCount = 4`) |
| Platform folders ios/linux/macos/windows | Standard Flutter hosts; primary showroom target is Android |

---

## 8. Large / tightly coupled

| File | Coupling |
|------|----------|
| `lib/main.dart` (~20k lines) | Extreme — UI + I/O + routing + pricing + persistence |
| `assets/data/products.csv` (~2.9 MB) | Catalog seed |
| `lib/master_products_sheet_builder.dart` | Isolated but complex |

---

## 9. Persistent runtime data (device, not in repo)

| Store | Location |
|-------|----------|
| Quote files | `{appDocuments}/showroom_quotes/quote_<id>.json` |
| Active index | `quotes_active.json` (+ legacy `quotes_index.json`) |
| Archive index | `quotes_archive.json` |
| Added customers | `{appDocuments}/added_customers.json` |
| Exports | Public Documents / Showroom export folders (Android channel) |

---

## 10. External data sources

| Source | URL / pattern |
|--------|----------------|
| Products Google Sheet CSV | `.../d/1UWduf2UklzxcnCA4dd6eKJN8QJb5gWm17k8F70fx1u8/export?format=csv&gid=1691211520` |
| Customers Google Sheet CSV | `.../d/1C9KzyNN7P7YVYvjpuCizXtxDdpfsp20UKewBAtStdCg/export?format=csv&gid=1371098168` |
| Product images | `https://showroom-images.netlify.app/images/{itemNumber}.jpeg` |

---

## 11. Unused / duplicate highlights

| Finding | Classification |
|---------|----------------|
| `QuoteBucketDefinition` vs `ProductTypeBucketMapping` | Duplicate concept |
| Dual JSON load paths for buckets | Partial migration |
| `test/widget_test.dart` placeholder | Unused as real test |
| Hidden Orders tab | Dormant UI |
| `scanner_test/` | Unused leftover |
| ~46× `catch (_)` in `main.dart` | Error-handling smell |

**No files deleted or modified by this inventory.**
