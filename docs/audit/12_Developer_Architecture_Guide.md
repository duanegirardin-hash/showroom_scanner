# 12 — Developer Architecture Guide

| Field | Value |
|-------|--------|
| Baseline | `refactor-split-main` @ `320f117` / tag `pre-full-audit` |
| Audience | Engineers continuing Showroom Scanner work |
| Rule | Describes **current** architecture; separates **risks** and **optional** improvements. Does **not** recommend a full rewrite. |

---

## 1. How to read this guide

| Layer | Meaning |
|-------|---------|
| **Current architecture** | What the code does at baseline |
| **Risk** | Confirmed or probable weakness (see Risk Register / SC-*) |
| **Optional improvement** | Incremental modularization or hardening — discuss before coding |

---

## 2. Repository structure

```
showroom_scanner/
├── lib/
│   ├── main.dart                         # ~20k lines — app UI + domain + persistence
│   ├── quote_bucket_routing.dart         # Pure Product Type / seasonal helpers (tested)
│   └── master_products_sheet_builder.dart # Isolated Setup “master products” workbook build
├── assets/
│   ├── data/
│   │   ├── products.csv                  # Bundled catalog fallback (~17.8k rows)
│   │   ├── customers.csv                 # Bundled customers (~258 rows)
│   │   ├── customer_walk_order.csv       # Walk-order positions
│   │   └── product_type_buckets.json     # Raw Product Type → bucketKey / displayLabel
│   └── sounds/                           # good_scan*, error_scan
├── test/
│   ├── summer_product_type_routing_test.dart
│   ├── widget_test.dart                  # Placeholder
│   └── audit/                            # Optional investigation-only tests
├── android/                              # applicationId com.example.showroom_scanner; debug signing for release
├── pubspec.yaml
└── docs/audit/                           # This audit documentation set
```

There is **no** layered `services/` / `models/` / `screens/` package tree yet. Almost all runtime behavior lives in `lib/main.dart`.

---

## 3. Entry point

```68:72:lib/main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ShowroomScannerApp());
}
```

- **`ShowroomScannerApp`**: Material theme (teal/coral tokens) + `home: ScannerHomePage`.
- Portrait lock is global.
- No DI framework; state is owned by `_ScannerHomePageState`.

---

## 4. Screens / navigation (current)

| Surface | Role |
|---------|------|
| **`ScannerHomePage` / `_ScannerHomePageState`** | Root; owns catalog, customers, quotes, focus, tabs |
| **Scan tab** (index 0) | Wedge/manual entry, live order panel, Load/Create Quote |
| **E-Catalog tab** (index 1) | Browse/filter catalog; add qty; merchandising chips |
| **Archive tab** (index 2) | Archived / confirmed quotes UI (`_ArchiveQuotesTab`) |
| **Setup tab** (index 3) | Admin: refresh data, walk-order viewer, catalog/master diagnostics |
| **`_CameraScannerPage`** | Full-screen `mobile_scanner` route |
| **`_WalkOrderViewerPage`** | Setup walk-order editor (in-memory copy of CSV) |
| **Dialogs** | Load Quote, customer pickers, import duplicate review, email menu, etc. |

**Orders tab**: `_OrderListTab` and related code remain, but Orders is **intentionally hidden** from `TabBar` (`_visibleTabCount = 4` = Scan / E-Catalog / Archive / Setup). Scan embeds a live order panel instead.

---

## 5. Models (in `main.dart` unless noted)

| Type | Purpose |
|------|---------|
| `Product` | Catalog row: item, UPC, prices, Product Type, PS/NET/discount flags, warehouse flags |
| `Customer` | CRM row + `discountPercent` parsing/normalization |
| `OrderLine` | Live workspace line (`product`, `quantity`, `scans`) |
| `SavedQuoteInfo` | Index row: id, name, customer fields, bucket, lifecycle timestamps |
| `QuoteBucketDefinition` | Runtime bucket (`bucketKey`, `displayLabel`) |
| `ProductTypeBucketMapping` | **`quote_bucket_routing.dart`** — same idea, shared/tested |
| `QuoteLifecycleStatus` | `active` \| `archived` \| `confirmed` |
| `ProductPricingState` | `regular` \| `discountEligible` \| `net` \| `ps` |
| Order-import structs | `OrderImportCsvRow`, skip/prepare/apply outcomes, duplicate resolution |
| `CustomerWalkOrderRow` | Walk position metadata |
| `MasterProductsBuildReport` | **`master_products_sheet_builder.dart`** |

Quote **payload** files are JSON maps (`quote_<id>.json`) with `name`, `customer`, `lines`/`items`, bucket fields, etc. — not a separate Dart class for the full document.

---

## 6. Services (current reality)

There is **no** formal service layer. Logical “services” are private methods on `_ScannerHomePageState` plus a few top-level helpers in `main.dart`:

| Concern | Primary symbols |
|---------|-----------------|
| Product load/parse | `_loadProductsOnStartup`, `_loadProductsFromWeb`, `_loadProductsFromAssets`, `compute(_parseProductsCatalogCsvIsolate, …)` |
| Customer load | `_loadCustomersFromAssets`, web refresh path, `added_customers.json` |
| Bucket config | `_loadQuoteBucketConfig` (+ tested `parseProductTypeBucketMappings`) |
| Quote CRUD / indexes | `_saveQuote`, `_loadQuoteById`, `_loadQuoteIndex`, archive helpers |
| Routing | `_ensureRoutingForProduct`, Pride/Everyday fallbacks |
| Pricing | `_productPricingState`, `_getDiscountedUnitPrice`, money helpers |
| Export / share | order CSV export paths, `_shareQuoteById`, `Share.shareXFiles` |
| Master sheet | `runUpdatedMasterProductsBuild` (library) |

**Risk:** God-object state class → high merge/conflict and regression cost (**SC-001**).  
**Optional:** Extract persistence, pricing, and routing into libraries with the same APIs; keep UI thin.

---

## 7. Widgets

Presentation widgets are mostly **private** classes at the bottom of `main.dart`:

- Scan: `_ScanTabLayout`, `_ScanQuotePanel`, `_ScanLiveOrderControlPanel`, order-line cards, search blocks
- E-Catalog: `_ECatalogTopActionBar`, `_ECatalogProductDetailSheet`, thumbnails
- Archive: `_ArchiveQuotesTab`
- Setup: `_SetupTab`
- Camera: `_CameraScannerPage`
- Shared order UI: `_OrderLineCard`, qty column, dismiss backgrounds

Widgets receive callbacks/data from `_ScannerHomePageState` (presentation extraction already started for Scan/Orders).

---

## 8. Data sources

| Source | URL / path | When used |
|--------|------------|-----------|
| Products Google Sheet CSV | Hard-coded `_productsCsvUrl` (spreadsheet id + `gid=1691211520`) | **First** on startup |
| Customers Google Sheet CSV | `_customersCsvUrl` (`gid=1371098168`) | Setup / refresh paths |
| Bundled products | `assets/data/products.csv` | Fallback if web fails |
| Bundled customers | `assets/data/customers.csv` | Always on cold start (before/alongside products) |
| Bucket map | `assets/data/product_type_buckets.json` | Startup with product load |
| Walk order | `assets/data/customer_walk_order.csv` | Debug/load for walk sorting |
| Locally added customers | `added_customers.json` under app documents | Setup; not synced to Sheets |
| Product images | `https://showroom-images.netlify.app/images/{itemNumber}.jpeg` | NetworkImage in Scan/ECatalog |

**Risks:** Startup network dependency (**SC-013**); hard-coded public sheet/image hosts (**SC-014**); Windows vs git casing of products asset (**SC-009**).

---

## 9. Startup pipeline (current)

Owned by `_ScannerHomePageState.initState` → post-frame callback:

1. Delay `_startupDeferAfterFirstFrame` (150 ms).
2. `_loadCustomersFromAssets()` (bundle delay 120 ms + isolate parse).
3. Fire-and-forget walk-order CSV debug load.
4. Fire-and-forget `_loadProductsOnStartup()`:
   - `_loadQuoteBucketConfig()`
   - `_loadProductsFromWeb()` → on success: audio + `readyToScan`
   - else `_loadProductsFromAssets()`
5. Parallel-ish: prune superseded empty duplicate quotes for all active-index customers.
6. Discard working order if no customer selected.
7. Enable scanner refocus; request focus (+ delayed retries).

Products CSV parse runs in a **`compute` isolate**. Customers similarly use isolate helpers.

---

## 10. Product / customer loading

### Products

- Parsed into `_productsByUpc` and `_productsByItemNumber`.
- Column requirements enforced in isolate (`producttype`, price fields, flags, warehouse columns).
- Mojibake repair applied to text fields.
- Missing Product Type mappings logged after load.

### Customers

- Loaded into `_customers` / `_customersByKey`.
- Discount cells normalized (`0.10` → 10%, clamp 0–100).
- Load failures are non-fatal (empty list + debug line).

### Staleness

- Successful web load replaces in-memory catalog for the session.
- Bundled CSV can lag the live sheet (**local staleness** risk when offline or web fails).
- App update replaces assets but **does not** wipe `showroom_quotes/` on device.

---

## 11. Quote model, lifecycle, indexes

### Lifecycle

`QuoteLifecycleStatus`: **active** → (export/email archive paths) **archived** → optional **confirmed**.

### On-disk layout (under `getApplicationDocumentsDirectory()/showroom_quotes/`)

| File | Role |
|------|------|
| `quote_<uuid>.json` | Full quote document |
| `quotes_active.json` | Active index (preferred) |
| `quotes_archive.json` | Archived / confirmed index |
| `quotes_index.json` | **Legacy** single index; migrated once into active/archive; left on disk |

Migration: if legacy exists and active does not, partition by status into the split files.

### Index hygiene

- Saves to active can remove the same id from archive (avoid dual listing).
- Empty-starter reuse only adopts **empty** persisted quotes for customer+bucket (`persistedQuoteDataIsEmptyForReuse`) — **SC-007** fix present.
- Startup / Load Quote prune superseded empty duplicates.
- Defensive index parse skips bad rows via silent `catch (_)` (**SC-002** risk).

### Workspace binding

- `_currentQuoteId`, `_activeQuoteBucketKey` / label, `_orderLines`, `_selectedCustomer`, quote name controllers.
- Bucket switches via `_ensureRoutingForProduct` (save → load existing or start new).

---

## 12. Persistence layout (exports & sync)

Beyond quotes:

| Path pattern | Role |
|--------------|------|
| `Showroom_Sync/Exported orders/<customer>/…` | Order CSV exports (Documents / Android public Documents / app-documents fallback) |
| Temporary directory | Email/share CSV + XLSX attachments |
| `added_customers.json` | Local customers |

Lifecycle persist: `AppLifecycleState.paused` / `hidden` → `_persistWorkingQuoteIfAny` (**SC-015**: force-kill mid-scan may still lose unsaved memory-only lines).

---

## 13. Product Type routing & bucket config

### Config

`product_type_buckets.json` → `mappings[rawType] = { bucketKey, displayLabel }`.

Includes dual Summer labels:

- `SUMMER GENERAL` / `SPRING/SUMMER - GENERAL` → `summer_general`
- `SUMMER TOYS` / `SPRING/SUMMER - TOYS` → `summer_toys`

### Resolution order (app)

1. Product Type (if present and not `"0"`)
2. Category
3. Pride token heuristics / Everyday default (in `main.dart`)

### Dual parse paths (**SC-012**)

- Runtime: `_loadQuoteBucketConfig` builds `QuoteBucketDefinition` maps.
- Tested: `parseProductTypeBucketMappings` / `lookupProductTypeBucketMapping` in `quote_bucket_routing.dart`.
- Normalization duplicated conceptually (`normalizeBucketLookupKey` vs `_normalizeBucketLookup`).

**Optional:** Single parser feeding UI maps (already partially extracted).

---

## 14. Scanner, focus, camera, manual entry

| Mode | Mechanism |
|------|-----------|
| Wedge / HID | Hidden/focused scanner field + focus reclaim timers |
| Quick / manual | `_quickEntryFocusNode` + Add path; then `_requestScannerFocusAfterManualEntry` |
| Camera | `_CameraScannerPage` + `MobileScanner` |
| Dedupe | `_scanDedupeMs` (80); pending queue serializes bursts |

Focus stack is intentionally complex (cooldown, single retry, tab-return delay, suspend flags for catalog tests). Scan subtree may not build off-tab → focus recovery on return (**SC-016**).

Audio: `audioplayers` good/error sounds after catalog ready.

---

## 15. Pricing

Precedence (`_productPricingState`):

1. **PS**
2. **NET**
3. **discountEligible** (customer `%` applied)
4. **regular**

Money: `_roundedUnitPrice`, `_lineTotalFromRoundedUnitPrice`, order totals for UI/export/email. List price shown separately where relevant (ECatalog / share XLSX).

**Risk:** Logic appears consistent in static review; **no unit tests** on pricing totals (**SC-011**). Phone verification still needed for discount edge cases.

---

## 16. E-Catalog

- Merchandising chips: new / everyday / home decor / seasonal / sale(PS) / all.
- Seasonal membership: `kEcatalogSeasonalProductTypes` (legacy Summer + live SPRING/SUMMER).
- Search + detail sheet + network thumbnails.
- Can navigate from import flow (`_ECatalogNavigationSource.importOrder`).
- Large in-memory filter over full catalog (**SC-017** performance risk).

---

## 17. Import / export / email / archive / confirmed

| Flow | Behavior (current) |
|------|-------------------|
| **Import order CSV** | Parse → duplicate review → route per Product Type → merge qty → multi-bucket saves |
| **Export order CSV** | `Showroom_Sync/Exported orders/…`; successful export can archive via `_moveActiveQuoteToArchiveAfterSuccessfulExport` |
| **Email / Share** | Builds CSV + XLSX + text; `Share.shareXFiles` |
| **Email Current / Customer** | `archiveAfterShare: true` → `_archiveActiveQuotesAfterEmailShare` after share sheet returns |
| **Email All Saved** | Share only; does not archive |
| **Confirmed** | Archive-tab path marks confirmed (`confirmedAt`); separate from email archive |

**Risks:**

- Share sheet return ≠ email delivered; archive **not** gated on `ShareResultStatus` (**SC-004**).
- Load Quote dialog copies index once; email-archive does not refresh dialog list (**SC-003**).

---

## 18. Image pipeline

- URL template: `https://showroom-images.netlify.app/images/<itemNumber>.jpeg`
- Used in ECatalog detail/thumbnails and order-line cards (`NetworkImage` / error builders).
- No local image cache layer in app code (relies on Flutter networking cache).
- Missing images fail softly in UI.

---

## 19. Diagnostic tags (temporary / debug)

| Tag / flag | Intent |
|------------|--------|
| `[QuoteDiag]` / `_quoteDiag` | Create Quote / routing / archive workspace |
| `[EmailShare]` / `[EmailArchive]` | Share + archive moves |
| `[SummerRouteDiag]` | Bucket config / summer mapping |
| `[ScanPerf]`, `_scanPerfDebug` | Scan timing |
| `[ScannerField]`, `[ManualEntry]` | Focus races |
| `[MasterBuildDiag]`, `[WhseDiag]` | Master builder |
| `[ProductsLoad]`, `[Customers]`, `[PersistExport]` | Data I/O |
| `_quoteRoutingDebug`, `_graduationRoutingDebug`, `_kspRoutingDebug`, index audit flags | Targeted routing/export |
| `_kScanRebuildInstrumentationEnabled` | Rebuild/setState traces (default false) |

**Risk:** Several “temporary” paths still print aggressively (**SC-006**), including stack traces on some loads.

---

## 20. Test architecture

| File | Role |
|------|------|
| `summer_product_type_routing_test.dart` | Asset JSON + pure routing/seasonal helpers |
| `widget_test.dart` | Placeholder only |
| `test/audit/*` | Investigation probes (optional; no prod changes) |

Session result: **15 passed** (see `06_Automated_Test_Report.md`). No integration/device tests in CI.

**Optional:** Unit-test money helpers, index migrate/prune, empty-starter gates, share/archive gating (with fakes).

---

## 21. Known coupling

1. **UI ↔ persistence ↔ routing** in one State class.
2. **Dual bucket parsers** (tested vs runtime).
3. **Focus ↔ tab visibility ↔ dialogs** tightly interleaved.
4. **Email archive ↔ Load Quote dialog** list ownership.
5. **Web catalog ↔ pricing ↔ ECatalog chips** share in-memory maps.
6. **Export success ↔ archive** vs **share open ↔ archive** (different gates).
7. Android **`com.example`** + debug signing coupled to install identity (**SC-005** / **SC-020**).

---

## 22. Recommended future modularization (incremental — not a rewrite)

Order of extraction that matches existing seams:

1. **`quote_bucket_routing.dart`** — finish single source of truth for JSON parse + normalize (delete duplicate loader logic).
2. **`quote_store.dart`** — directory paths, index migrate/load/save, archive/confirm moves (pure Dart + `dart:io`).
3. **`catalog_loader.dart`** — CSV isolate jobs + web/asset fetch.
4. **`pricing.dart`** — `ProductPricingState` + money rounding/totals (easy unit tests).
5. **`quote_share_export.dart`** — CSV/XLSX/text builders + share orchestration (inject `Share` for tests).
6. Keep **`master_products_sheet_builder.dart`** isolated (already good).
7. Peel **Scan / ECatalog / Archive / Setup** into `widgets/` or `features/` only after stores stabilize.

Avoid: big-bang rewrite, premature BLoC/Riverpod unless team wants it; the State object can shrink gradually behind facades.

---

## 23. Architecture verdict

| Statement | Rating |
|-----------|--------|
| App is a **monolithic but coherent** showroom quoting tool | Accurate |
| Core domain (buckets, empty-starter, archive indexes) shows **deliberate** recent hardening | Accurate |
| Maintainability bottleneck is **file size / coupling**, not unknown chaos | Accurate |
| Full rewrite required | **Not evidenced** — incremental splits + tests are the proportionate path |

Cross-ref: `13_Risk_Register.md`, `14_Full_App_Audit_Report.md`, static findings **SC-001…SC-020**.
