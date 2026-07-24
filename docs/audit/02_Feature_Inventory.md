# 02 — Feature Inventory

| Field | Value |
|-------|--------|
| Baseline | `320f117` / `pre-full-audit` / `refactor-split-main` |
| Primary source | `lib/main.dart` (+ `quote_bucket_routing.dart`, `master_products_sheet_builder.dart`) |
| Visible tabs | **Scan**, **E-Catalog**, **Archive**, **Setup** (Orders tab UI exists but is hidden) |

Phone verification: mark **NEEDS PHONE VERIFICATION** where behavior depends on device, share sheet, camera, or live network.

---

## F-01 Application and startup

| Field | Detail |
|-------|--------|
| Purpose | Portrait lock, paint UI, load customers/products/buckets, prune empty duplicate quotes, focus scanner |
| UI entry | App launch → `ShowroomScannerApp` → `ScannerHomePage` |
| Files / symbols | `main()`; `_ScannerHomePageState.initState`; `_loadCustomersFromAssets`; `_loadProductsOnStartup`; `_loadQuoteBucketConfig`; `_pruneSupersededEmptyDuplicateQuotesForAllActiveIndexCustomers`; `_initAudio` |
| Call path | `main` → `runApp` → `initState` → post-frame: customers → products (web then assets) → prune → scanner focus |
| Data read | `customers.csv`, products (Sheet or `products.csv`), `product_type_buckets.json`, quote indexes |
| Data written | Prune may delete empty `quote_*.json` / rewrite `quotes_active.json` |
| Expected | Prefer live products CSV; fall back to bundled; Ready to scan when catalog OK |
| Errors | Product asset failure → not ready; customer failure non-fatal |
| Side effects | Network on startup; audio init; diagnostic prints |
| Tests | None |
| Phone verification | **NEEDS PHONE VERIFICATION** |
| Risks | Large CSV parse; network dependency; prune before user action |

**Also covered:** app resume/background → `didChangeAppLifecycleState` → `_persistWorkingQuoteIfAny`; orientation locked portrait in `main()`.

---

## F-02 Customers

| Field | Detail |
|-------|--------|
| Purpose | Select customer; discounts; local add; sheet refresh |
| UI entry | Scan customer control; Setup **LOAD CUSTOMERS**, **Add Customer** |
| Symbols | `Customer`; `_loadCustomersFromAssets`; `_loadCustomersFromSheet`; `_showAddCustomerDialog`; `added_customers.json` |
| Data R/W | R: assets + Sheet + `added_customers.json`. W: local adds only (not synced to Sheets) |
| Expected | Discount % from CSV; Create Quote can open picker if none selected |
| Tests | None |
| Phone verification | **NEEDS PHONE VERIFICATION** |
| Risks | Wrong customer before scanning; dedup by normalized name |

---

## F-03 Quotes

| Feature area | Entry | Key symbols | Notes |
|--------------|-------|-------------|-------|
| Create Quote | Scan/E-Catalog **Create Quote** | `_confirmNewQuote`, `_startNewQuote` | Clears workspace; empty-starter-only reuse when routing with null id |
| Load Quote | **Load Quote** | `_showLoadQuoteDialog`, `_loadQuoteById` | Dialog copies list once in `initState` |
| Naming | Auto / dialog | quote name fields | Bucket display label often prefixes name |
| Save / persistence | Lifecycle, routing, explicit | `_saveQuote` | Writes `quote_<id>.json` + active index |
| Active / archive / confirmed | Load Quote + Archive tab | indexes + `QuoteLifecycleStatus` | See F-11/F-12 |
| Bucket routing | Implicit on scan/import | `_ensureRoutingForProduct` | Auto Product Type separation |
| Empty starter reuse | Routing | `persistedQuoteDataIsEmptyForReuse` | Safe: does **not** adopt non-empty when Create Quote left id null |
| Full Catalog Quote tool | Setup (debug) | Build Full Catalog Test Quote | Do not use during normal orders |
| Indexes | Disk | `quotes_active.json`, `quotes_archive.json`, legacy `quotes_index.json` | Individual `quote_<id>.json` |

| Field | Detail |
|-------|--------|
| Tests | None for save/load/archive |
| Phone verification | **NEEDS PHONE VERIFICATION** |
| Risks | Stale Load Quote list after email-archive; index/file drift; silent catch on malformed JSON |

---

## F-04 Product Type buckets

Configured in `assets/data/product_type_buckets.json` + runtime `_resolveQuoteBucketForProduct` / `lookupProductTypeBucketMapping`.

| Raw key(s) | bucketKey | displayLabel |
|------------|-----------|--------------|
| CALENDAR | calendar | CALENDAR |
| CANADA DAY | canada_day | Canada Day |
| CHINESE NEW YEAR | chinese_new_year | CHINESE NEW YEAR |
| CHRISTMAS | christmas | CHRISTMAS |
| DIWALI | diwali | DIWALI |
| EASTER | easter | EASTER |
| EVERYDAY | every_day | EVERYDAY |
| FALL/WINTER ESSENTIALS | fall_winter | FALL/WINTER ESSENTIALS |
| FATHER'S DAY | fathers_day | FATHER'S DAY |
| FIFA | fifa | FIFA |
| GIFTCRAFT | giftcraft | GIFTCRAFT |
| GRADUATION | graduation | GRADUATION |
| HALLOWEEN | halloween | HALLOWEEN |
| HANUKKAH | hanukkah | HANUKKAH |
| HARVEST | harvest | HARVEST |
| KSP | ksp | KSP |
| MOTHER'S DAY | mothers_day | MOTHER'S DAY |
| NEW YEARS | new_years | NEW YEARS |
| PRIDE | pride | PRIDE |
| ST PATRICKS DAY / ST PATRICK'S DAY | st_patricks_day | dual display variants |
| SUMMER GENERAL | summer_general | SUMMER GENERAL |
| SUMMER TOYS | summer_toys | SUMMER TOYS |
| **SPRING/SUMMER - GENERAL** | **summer_general** | **SUMMER GENERAL** |
| **SPRING/SUMMER - TOYS** | **summer_toys** | **SUMMER TOYS** |
| VALENTINE'S DAY | valentines_day | VALENTINE'S DAY |

**Normalization:** `normalizeBucketLookupKey` (trim, lower, apostrophe unify, `&`→and, non-alnum→space).  
**Fallback:** Product Type → Category → Pride heuristic → Everyday.  
**Unmapped types:** Everyday (default).  
**Tests:** Summer aliases + sample seasonals in `summer_product_type_routing_test.dart`.  
**Phone verification:** Live sheet Product Types vs JSON.

---

## F-05 Scanning

| Mode | Entry | Symbols | Notes |
|------|-------|---------|-------|
| Bluetooth HID / keyboard wedge | Hidden focus field on Scan | `_handleScannerCharacter`, `_processScannerBuffer`, `_processScan` | Carriage return / Enter submits buffer |
| Camera | **Scan with Camera** | `_CameraScannerPage`, `mobile_scanner` | Permission CAMERA; cooldown ~1200ms |
| Manual / Quick Entry | Scan fields | `_processScan` / quick-entry path | Same lookup as wedge |
| Focus reclaim | Timers/post-frame | `_scheduleScannerRefocus` | Risk of lost focus after dialogs |
| Sounds | Scan success/error | audioplayers + assets | good_scan / error_scan |
| Duplicate cooldown | Camera path | camera handler | HID cooldown separate / limited |

| Tests | None |
| Phone | **NEEDS PHONE VERIFICATION** |
| Risks | Focus fights; scan while dialogs open; tab not building Scan subtree |

---

## F-06 Order lines

| Action | Behavior |
|--------|----------|
| Add | Lookup → routing → `_addProduct`; qty starts at MOQ |
| Increase / decrease | Line card controls; recalculate totals |
| Delete | Swipe/dismiss or remove control |
| Merge | Same item bumps qty (by MOQ) and moves toward top |
| MOQ / case | Min order from catalog; case qty displayed / rounding helpers |
| Persistence | Via `_saveQuote` / lifecycle persist |
| Totals / counts | `_recalculateTotals`; item + scan counts on UI |

Tests: none. Phone: **NEEDS PHONE VERIFICATION**.

---

## F-07 Pricing

| Concept | Behavior (code) |
|---------|-----------------|
| Precedence | **PS > NET > discountEligible > regular** (`ProductPricingState`) |
| Customer discount | Applied when discount-eligible: price × (1 − %/100) |
| PS | Reg + Sale display |
| NET | NET price |
| DISCOUNT / List / Price | CSV columns drive eligibility and base |
| Invalid / blank | Parsers tend toward 0 / non-eligible |
| Export vs display | Built from same line fields; verify on phone |

Tests: none. Phone: **NEEDS PHONE VERIFICATION**.

---

## F-08 Product information

Fields used from catalog: Item Number, Description, UPC, Category, Sub-Category, Product Type, New Release, Whse 1/2 Availability, MOQ, Case Qty, prices, image URL pattern.

UI: Scan tiles; E-Catalog list/detail sheet. Missing image: Flutter Image error (silent). Phone: **NEEDS PHONE VERIFICATION**.

---

## F-09 ECatalog

| Entry | Tab **E-Catalog** |
| Chips | New Items, Everyday, Decor & Giftware, Seasonal, Sale, In Order, In Stock Only, Previously Ordered Only, Clear Filters |
| Search | Item / UPC / description (combined search field) |
| Filters | Category, sub-category, Product Type, merchandising chips |
| Seasonal set | `kEcatalogSeasonalProductTypes` (includes both SUMMER * and SPRING/SUMMER - *) |
| Add to quote | Same routing as scan; requires scannable digits |
| Walk order / Never Add / Previously Ordered | Walk-order CSV + customer context |
| Performance | Full catalog in memory; list filter in Dart |

Tests: seasonal membership only. Phone: **NEEDS PHONE VERIFICATION**.

---

## F-10 Import

| Entry | E-Catalog **Import Order** (OneDrive → Import folder copy) |
| Types | CSV / Excel via `file_picker` + `csv`/`excel` |
| Behavior | Multi-file supported in flow; item/UPC lookup; MOQ rounding; skip invalid; duplicate review; multi-bucket routing; save touched quotes |
| Reports | Skip/missing recorded; snackbars |
| Tests | None |
| Phone | **NEEDS PHONE VERIFICATION** |

---

## F-11 Export and email

| Action | UI | Archives? |
|--------|-----|-----------|
| Export Current Quote Only | E-Catalog / order export actions | Export path may archive via `_moveActiveQuoteToArchiveAfterSuccessfulExport` |
| Export All Quotes | E-Catalog | Same family of archive-after-export helpers |
| Email Current Quote Only | Load Quote email menu | **Yes** — after share (`archiveAfterShare: true`); copy says moves to Archive |
| Email Customer Quotes | same | **Yes** for applicable active quotes |
| Email All Saved Quotes | same | **No** — share only |
| Share sheet | `Share.shareXFiles` | Return ≠ confirmed email sent |

| Risks | Archive not gated on `ShareResultStatus`; Load Quote list not refreshed after archive |
| Tests | None |
| Phone | **NEEDS PHONE VERIFICATION** |

---

## F-12 Archive and confirmed

| Entry | Tab **Archive** |
| Actions | Restore to active; confirm; delete; purge |
| Indexes | `quotes_archive.json`; may delete `quote_*.json` |
| Active clear | Email-archive of current may `_startNewQuote` / clear workspace |
| Missing file | Handled with logs / skip in some export paths |
| Tests | None |
| Phone | **NEEDS PHONE VERIFICATION** |

---

## F-13 Setup and admin

| Action | Notes |
|--------|-------|
| LOAD PRODUCTS | `_loadProductsFromWeb` |
| LOAD CUSTOMERS | `_loadCustomersFromSheet` |
| Add Customer | Local JSON |
| Walk Order Editor | Export Walk Order CSV, renumber, NeverAdd |
| Build Full Catalog Test Quote | **Debug only (`kDebugMode`)** — risk if used mid-showroom |
| Export Full Catalog / Master sheets | Debug Setup tools |
| Build Updated Master Products Sheet | `runUpdatedMasterProductsBuild` |

Do not use full-catalog / master tools during normal customer orders. Phone: **NEEDS PHONE VERIFICATION**.

---

## Cross-feature stores

| Store | Features |
|-------|----------|
| In-memory catalog maps | Scan, E-Catalog, Import, Pricing |
| `showroom_quotes/*` | Quotes, routing, export, email, archive |
| `added_customers.json` | Customers / Setup |
| Google Sheets | Startup/Setup refresh |
| Netlify images | Product thumbs / detail |
