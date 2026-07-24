# 05 — Workflow Traces

| Field | Value |
|-------|--------|
| Baseline | `320f117` / tag `pre-full-audit` / branch `refactor-split-main` |
| Primary source | `lib/main.dart`, `lib/quote_bucket_routing.dart`, `assets/data/product_type_buckets.json` |
| Method | Static call-path tracing (no phone run in this pass) |
| Persistence root | `{appDocuments}/showroom_quotes/` |
| Index files | `quotes_active.json`, `quotes_archive.json` (legacy `quotes_index.json` migrated once) |
| Quote files | `quote_<id>.json` |
| Products sheet | `gid=1691211520` |
| Customers sheet | `gid=1371098168` |
| Image URL | `https://showroom-images.netlify.app/images/{itemNumber}.jpeg` |

**Tabs (exact labels):** Scan · E-Catalog · Archive · Setup  
(`_visibleTabCount = 4`. An `_OrderListTab` / Orders UI still exists in code with labels such as **Import Order (OneDrive → Import folder)** and **Export Order (Saved to OneDrive / Share)**, but it is **not** shown in the tab bar.)

**Shared note on saves:** Quantity/scan/delete edits update memory immediately. Disk write via `_saveQuote` is triggered by routing switches, Create Quote (when saving current), Load Quote open, import apply, export/email prep, and app lifecycle `paused`/`hidden` (`_persistWorkingQuoteIfAny`). Force-kill without those paths can drop unsaved line edits — **NEEDS PHONE VERIFICATION** for kill timing.

**Automated tests (repo):** `test/summer_product_type_routing_test.dart` (bucket aliases + Seasonal membership). `test/widget_test.dart` is a placeholder. Almost all workflows below: **no automated coverage**.

---

## Trace template fields

Each workflow uses: User action · UI handler · Call sequence · State changes · Files R/W · Indexes · Screen result · Success · Failure · Safeguards · Missing safeguards · Diagnostic tags · Tests · Phone test.

---

## 1. App startup

| Field | Evidence |
|-------|----------|
| **User action** | Launch app icon / `flutter run` |
| **UI handler** | `main()` → `ShowroomScannerApp` → `ScannerHomePage.initState` |
| **Call sequence** | `WidgetsFlutterBinding.ensureInitialized` → portrait lock → `runApp` → `initState`: post-frame → delay → `_loadCustomersFromAssets` → unawaited `_debugLoadCustomerWalkOrderCsv` → unawaited `_loadProductsOnStartup` → `_pruneSupersededEmptyDuplicateQuotesForAllActiveIndexCustomers` → `_discardWorkingOrderIfNoCustomerSelected` → enable scanner refocus → `_requestScannerFocus` (+ delayed pulses 90ms/320ms) |
| **State changes** | `_customers` filled or cleared; `_loadingProducts` / `_readyToScan`; empty workspace if no customer; `_scannerStartupRefocusEnabled = true` |
| **Files read** | `assets/data/customers.csv`; `assets/data/customer_walk_order.csv`; `assets/data/product_type_buckets.json` (inside product load); products web URL or `assets/data/products.csv`; may read `showroom_quotes/quotes_active.json` during prune |
| **Files written** | Possibly rewrite active index during prune of empty dupes; none on cold empty install |
| **Indexes** | May remove superseded empty duplicate active rows |
| **Screen result** | Scan tab; status toward `Ready to scan` when products OK |
| **Success** | Customers parsed; products loaded (web or asset); scanner field focusable |
| **Failure** | Asset/web load errors → snackbars / debug status lines; prune failure logged `[Startup] prune-all failed` |
| **Safeguards** | `mounted` checks; non-fatal customer load; product web→asset fallback; discard orphan workspace without customer |
| **Missing safeguards** | No automatic restore of last open quote into workspace on cold start (must **Load Quote**) |
| **Diagnostic tags** | `[QuoteDiag]`, `[Customers]`, `[Products]`, `[WalkOrder]`, `[Startup]` |
| **Tests** | None for startup pipeline |
| **Phone test** | Cold launch online/offline; confirm customers + products + Ready to scan |

---

## 2. Load customers

| Field | Evidence |
|-------|----------|
| **User action** | Automatic at startup; or Setup → **LOAD CUSTOMERS** |
| **UI handler** | `_loadCustomersFromAssets` / `_loadCustomersFromSheet` |
| **Call sequence** | Startup: `rootBundle.loadString('assets/data/customers.csv')` → `_parseAndStoreCustomers` → schedule `_reapplyLocalAddedCustomers`. Setup: `http.get(_customersCsvUrl)` (`gid=1371098168`) → parse → merge local `added_customers.json` |
| **State** | `_customers`, `_customersByKey`, optional reselect; walk-order sync |
| **Files R** | Asset CSV or sheet export; `added_customers.json` |
| **Files W** | None on sheet load (local adds write `added_customers.json` elsewhere) |
| **Indexes** | None |
| **Screen** | Snackbar `Updating customers...` / success or failure |
| **Success** | Non-empty customer list usable by picker |
| **Failure** | HTTP ≠200 / parse fail → snackbar; asset fail clears list |
| **Safeguards** | Local added customers reapplied after sheet refresh |
| **Missing** | Sheet vs asset staleness not versioned for user |
| **Tags** | `[Customers]` |
| **Tests** | None |
| **Phone** | Setup refresh with network; offline after prior asset load |

---

## 3. Load products from Google Sheets

| Field | Evidence |
|-------|----------|
| **User action** | Startup (`_loadProductsOnStartup`) or Setup → **LOAD PRODUCTS** |
| **UI handler** | `_loadProductsFromWeb` |
| **Call sequence** | `_loadQuoteBucketConfig` (startup path) → `http.get(_productsCsvUrl)` (`gid=1691211520`) → `_parseAndStoreProducts(..., sourceLabel: 'Google Sheets CSV')` → snackbar with count |
| **State** | Product maps/indexes; `_catalogCount`; `_loadingProductsFromWeb` |
| **Files R** | Remote CSV; buckets JSON on startup path |
| **Files W** | None (in-memory catalog) |
| **Indexes** | In-memory UPC/item maps rebuilt |
| **Screen** | `Updating products...` then `Products updated successfully (N loaded)` |
| **Success** | HTTP 200 + parse |
| **Failure** | Non-200 / exception → snackbar; startup then falls through to assets |
| **Safeguards** | Re-entrancy guard `_loadingProductsFromWeb` |
| **Missing** | No local cache file of last successful sheet download |
| **Tags** | `[Products][Verify]`, `[Products]` |
| **Tests** | None |
| **Phone** | Airplane mode vs Wi-Fi; confirm count |

---

## 4. Product-load fallback

| Field | Evidence |
|-------|----------|
| **User action** | Automatic when web load returns false at startup |
| **UI handler** | `_loadProductsOnStartup` → `_loadProductsFromAssets` |
| **Call sequence** | `rootBundle.loadString('assets/data/products.csv')` → `_parseAndStoreProducts(..., 'Built-in catalog')` → `_initAudio` → `_readyToScan = true` |
| **State** | Same product state; status `Ready to scan` or `Error loading built-in catalog` |
| **Files R** | Bundled `products.csv` |
| **Files W** | None |
| **Success** | Parse completes |
| **Failure** | Catch sets `_readyToScan = false` |
| **Safeguards** | Audio still init on failure path |
| **Missing** | User may not see clear “using offline catalog” banner (status/debug only) |
| **Tags** | `[Products]` |
| **Phone** | Kill network before launch; confirm built-in catalog works |

---

## 5. Select customer

| Field | Evidence |
|-------|----------|
| **User action** | Tap customer control / Create Quote with none selected / picker dialogs |
| **UI handler** | `_showSelectCustomerDialog` / `_runCustomerPickerDialog` |
| **Call sequence** | Dialog with search → select → set `_selectedCustomer` → `_syncCustomerWalkOrderEnabledForCustomer` → `_refreshPreviouslyOrderedHistoryForSelectedCustomer` (async) |
| **State** | Selected customer + walk-order flags; previously-ordered history for ECatalog |
| **Files R** | Archive quote files when refreshing previously-ordered history |
| **Files W** | None for selection alone |
| **Screen** | Customer name shown; snackbar if customers empty |
| **Success** | Non-null `_selectedCustomer` |
| **Failure** | Cancel picker; empty list |
| **Safeguards** | Working-order mutations gated by `_requireSelectedCustomerForWorkingOrder` |
| **Missing** | Easy to scan after wrong customer until user notices |
| **Tags** | `[WalkOrder]` |
| **Phone** | Search + select; switch customer mid-quote behavior |

---

## 6. Create Quote

| Field | Evidence |
|-------|----------|
| **User action** | Tap **Create Quote** (Scan or E-Catalog bar) |
| **UI handler** | `_confirmNewQuote` → `_startNewQuote` |
| **Call sequence** | If no customer → picker. Confirm dialog. If current lines → `_saveQuote`. Then `_startNewQuote(customer)` clearing lines, `_currentQuoteId = null`, Everyday (default) bucket, auto name `EVERYDAY QUOTE_...` / bucket-prefixed |
| **State** | Empty workspace; new display name; scanner focus |
| **Files R/W** | Save may write `quote_<id>.json` + `quotes_active.json` for prior quote |
| **Indexes** | Prior quote updated if saved |
| **Screen** | Dialog **Create Quote**; status `Create quote started` |
| **Success** | Empty starter; customer set |
| **Failure** | Cancel; no customers loaded |
| **Safeguards** | **Empty-starter-only** later in routing: when already on target bucket with `_currentQuoteId == null`, only `_findEmptyPersistedQuoteIdForCustomerBucket` is adopted — **does not** load a huge non-empty catalog quote into a fresh Create Quote workspace (`reason=create_quote_safe_empty_starter_only`) |
| **Missing** | Create Quote itself does not delete existing full-catalog quotes on disk |
| **Tags** | `[QuoteDiag]`, `[QuoteStarter]` |
| **Tests** | None (behavior documented in code comments) |
| **Phone** | Create Quote after a large saved Everyday quote exists — must stay empty |

---

## 7. Scan first product

| Field | Evidence |
|-------|----------|
| **User action** | Bluetooth wedge types UPC+Enter into hidden scanner field, or camera/manual |
| **UI handler** | Scanner `TextField` → `_handleScannerCharacter` / submit → `_processScannerBuffer` → `_enqueueScan` → `_drainScanQueue` → `_processScan` |
| **Call sequence** | Dedupe 80ms → `_findProduct` → `_ensureRoutingForProduct` → `_addProduct` (qty = `minOrderQty`) → beep → focus restore |
| **State** | First `OrderLine`; totals; status `Added to {bucket} quote` |
| **Files** | Usually memory only until later save |
| **Success** | Line appears at top of Scan order list |
| **Failure** | Not found → `UPC / ITEM NOT FOUND` + error sound; no customer → snackbar |
| **Safeguards** | Scan queue; 80ms dedupe; customer gate |
| **Missing** | Save not immediate after first scan unless lifecycle/routing |
| **Tags** | `[ScanLookup]`, `[ScanPerf]`, `[QuoteDiag]`, `[SummerRouteDiag]` |
| **Phone** | First scan with customer selected |

---

## 8. Resolve Product Type

| Field | Evidence |
|-------|----------|
| **User action** | Implicit on add/scan/import/ECatalog |
| **UI handler** | `_resolveQuoteBucketForProduct` in `lib/main.dart` (runtime path) |
| **Call sequence** | Normalize raw Product Type via `normalizeBucketLookupKey` → map in `_quoteBucketsByRawType` (from `product_type_buckets.json` via `_loadQuoteBucketConfig`) → else Category → else Pride token → else Everyday (`every_day`) |
| **State** | Returns `QuoteBucketDefinition` |
| **Files R** | Config loaded earlier |
| **Success** | Known mapping hit |
| **Failure** | Unmapped → Everyday default (may be wrong merchandising) |
| **Safeguards** | Absent/`0` Product Type → Everyday only (no category route) |
| **Missing** | Silent Everyday fallback for typos. Shared helpers `lookupProductTypeBucketMapping` / `parseProductTypeBucketMappings` in `quote_bucket_routing.dart` are used by unit tests but **not** called by the app resolve path (duplication / drift risk if one side changes) |
| **Tags** | `[Routing]`, `[SummerRouteDiag]`, `[KSP Routing]`, `[Graduation Routing]` |
| **Tests** | `summer_product_type_routing_test.dart` for Summer + Halloween/Harvest/Mother’s Day/Everyday (tests the shared helper + JSON, not `_resolveQuoteBucketForProduct` itself) |
| **Phone** | Spot-check live sheet Product Types |

---

## 9. Resolve quote bucket

| Field | Evidence |
|-------|----------|
| **User action** | Same as #8 |
| **UI handler** | `_logicalQuoteBucketKey` + bucket definition |
| **Call sequence** | Bucket key canonicalized (`every_day`, `summer_general`, `summer_toys`, …) for index identity |
| **Summer** | `SPRING/SUMMER - GENERAL` & `SUMMER GENERAL` → `summer_general` / label **SUMMER GENERAL**; Toys → `summer_toys` / **SUMMER TOYS** (separate) |
| **Tags** | `[SummerRouteDiag]` |
| **Phone** | Scan one General + one Toys item → two quotes |

---

## 10. Reuse or create quote

| Field | Evidence |
|-------|----------|
| **User action** | Scan/add when Product Type bucket differs from active |
| **UI handler** | `_ensureRoutingForProduct` |
| **Call sequence** | If lines → `_saveQuote`. `_findExistingQuoteIdForCustomerBucket` (prefers non-empty). If found → `_loadQuoteById`. Else `_startNewQuote(..., initialBucket: bucket)`. If already on bucket & id null → empty-starter adopt only |
| **State** | Switch `_currentQuoteId`, lines, bucket label |
| **Files R/W** | Read/write quote JSON + active index on save/load |
| **Indexes** | Updated on save |
| **Screen** | Status `Switched to {label} quote` or new starter |
| **Safeguards** | Empty-starter-only when id null on same bucket; prune empty dupes elsewhere |
| **Missing** | Concurrent edits on two devices not supported |
| **Tags** | `[QuoteDiag]`, `[QuoteImport]`, `[Routing]` |
| **Phone** | Alternate Everyday ↔ Halloween scans |

---

## 11. Add order line

| Field | Evidence |
|-------|----------|
| **User action** | Successful scan / Add / ECatalog add |
| **UI handler** | `_addProduct` |
| **Call sequence** | Customer gate → merge by line key or insert → `_recalculateTotals` → feedback sounds |
| **State** | `_orderLines`, `_orderLineByKey`, `_itemsScanned`, selection |
| **Files** | Memory until save |
| **Success** | Status `Added to …` |
| **Failure** | Returns false if no customer |
| **Safeguards** | Line merge + move to top |
| **Missing** | No undo |
| **Tags** | `SETSTATE_TRACE[item_add]` (debug flag) |
| **Phone** | New vs repeat SKU |

---

## 12. Save quote

| Field | Evidence |
|-------|----------|
| **User action** | Implicit (Load Quote, export, routing, lifecycle, Create Quote with items) — no dedicated **Save Quote** button |
| **UI handler** | `_saveQuote` |
| **Call sequence** | Build JSON → write `quote_<id>.json` → upsert `quotes_active.json` with `quoteStatus=active`. If id archive-only → payload-only write, refuse reinsert |
| **State** | Assigns `_currentQuoteId` when minted |
| **Files W** | `showroom_quotes/quote_<id>.json`, `quotes_active.json` |
| **Indexes** | Active index upsert; newest-first semantics elsewhere |
| **Success** | Files flushed |
| **Failure** | Logged; archive-side special path |
| **Safeguards** | Refuse active reinsert for archived id; drop stale workspace id |
| **Missing** | Non-atomic multi-file update (index + quote); kill mid-write risk |
| **Tags** | `[SaveQuote]`, `[QuoteDiag]` |
| **Phone** | Background app then reopen → **Load Quote** sees lines |

---

## 13. Scan another Product Type

| Field | Evidence |
|-------|----------|
| **User action** | Scan item whose Product Type maps to a different bucket than the active quote |
| **UI handler** | `_processScan` → `_ensureRoutingForProduct` → `_addProduct` |
| **Call sequence** | `_saveQuote` if lines → `_findExistingQuoteIdForCustomerBucket` or `_startNewQuote` → `_loadQuoteById` if reuse → `_addProduct` |
| **State changes** | `_currentQuoteId`, `_orderLines`, `_activeQuoteBucketKey`/`Label`, status |
| **Files read** | Candidate `quote_<id>.json`; active index |
| **Files written** | Prior quote JSON + `quotes_active.json` on save |
| **Indexes** | Active index updated for saved prior quote |
| **Screen result** | Status `Switched to {displayLabel} quote` then `Added to …` |
| **Success** | Item lands on correct bucket quote |
| **Failure** | No customer; product not found (earlier in scan) |
| **Safeguards** | Logical customer+bucket identity; empty-starter-only when id null on same bucket |
| **Missing safeguards** | User may not notice silent switch without reading status |
| **Diagnostic tags** | `[Routing]`, `[SummerRouteDiag]`, `[QuoteDiag]` |
| **Tests** | Alias mapping covered; full switch UI not automated |
| **Phone test** | Everyday then Halloween; Summer General then Summer Toys |

---

## 14. Switch quote

| Field | Evidence |
|-------|----------|
| **User action** | Automatic (#13) or **Load Quote** → select row |
| **UI handler** | `_loadQuoteById` / `_ensureRoutingForProduct` |
| **Call sequence** | Active-eligible check → read JSON → rebuild lines/customer/bucket → focus scanner |
| **State changes** | Full workspace replaced with loaded quote |
| **Files read** | `quote_<id>.json`, `quotes_active.json` (eligibility) |
| **Files written** | None on load alone (prior may have been saved by Load Quote open) |
| **Indexes** | Unchanged on load |
| **Screen result** | Quote name, lines, customer restored |
| **Success** | Active-eligible file loads |
| **Failure** | Missing file removes index row; archive-only blocked with restore message |
| **Safeguards** | Will not load archive-only ids via this path |
| **Missing safeguards** | StackTrace always printed on load (noisy diagnostics) |
| **Diagnostic tags** | `[QuoteDiag]` |
| **Tests** | None |
| **Phone test** | Load between two active bucket quotes |

---

## 15. Change quantity

| Field | Evidence |
|-------|----------|
| **User action** | Line **+** / **−** or **Edit Quantity** → **Save** |
| **UI handler** | `_increaseLineQty` / `_decreaseLineQty` / `_showEditQuantityDialog` |
| **Call sequence** | Customer gate → qty +=/-= `minOrderQty` or set absolute → `_recalculateTotals` |
| **State changes** | Line quantity, totals, status; decrease below 1 removes line |
| **Files read** | None |
| **Files written** | Not immediate; later `_saveQuote` / lifecycle persist |
| **Indexes** | Unchanged until save |
| **Screen result** | `Quantity increased/decreased/updated` |
| **Success** | Qty > 0 after edit |
| **Failure** | Edit ≤0 rejected; no customer snackbar |
| **Safeguards** | Dialog cancels restore scanner focus |
| **Missing safeguards** | Unsaved qty if force-killed before persist |
| **Diagnostic tags** | None dedicated |
| **Tests** | None |
| **Phone test** | Change qty → background → Load Quote |

---

## 16. Delete an item

| Field | Evidence |
|-------|----------|
| **User action** | Delete control → **Delete Item** → **Delete** |
| **UI handler** | `_confirmDeleteLine` |
| **Call sequence** | Confirm → remove list/map → totals; empty → `_resetQuoteDisplayAndScanState` |
| **State changes** | Lines/maps/selection/status `Item deleted` |
| **Files read** | None |
| **Files written** | Memory until later save |
| **Indexes** | Unchanged until save |
| **Screen result** | Line gone |
| **Success** | Confirm true |
| **Failure** | Cancel leaves line |
| **Safeguards** | Confirmation dialog; `_editDialogOpen` blocks scanner reclaim mid-dialog |
| **Missing safeguards** | No undo; disk not updated immediately |
| **Diagnostic tags** | None dedicated |
| **Tests** | None |
| **Phone test** | Delete middle vs last line |

---

## 17. Close app

| Field | Evidence |
|-------|----------|
| **User action** | Home / switch app / back |
| **UI handler** | `didChangeAppLifecycleState` |
| **Call sequence** | `paused`/`hidden` → `unawaited(_persistWorkingQuoteIfAny)` → `_saveQuote` if lines or id |
| **State changes** | Disk catch-up of workspace |
| **Files read** | None required |
| **Files written** | `quote_<id>.json`, `quotes_active.json` when path runs |
| **Indexes** | Active upsert |
| **Screen result** | App backgrounds |
| **Success** | Persist completes |
| **Failure** | `[PersistWorkingQuote] failed` logged |
| **Safeguards** | Skips during import/`_loadingProducts` |
| **Missing safeguards** | Force-stop may skip lifecycle — **NEEDS PHONE VERIFICATION** |
| **Diagnostic tags** | `[PersistWorkingQuote]` |
| **Tests** | None |
| **Phone test** | Soft background vs force stop |

---

## 18. Reopen app

| Field | Evidence |
|-------|----------|
| **User action** | Launch again |
| **UI handler** | Same as #1 startup |
| **Call sequence** | Customers/products/prune; **no** auto `_loadQuoteById` of last session |
| **State changes** | Fresh empty workspace |
| **Files read** | Startup assets/web + prune may touch indexes |
| **Files written** | Possible prune rewrites |
| **Indexes** | May prune empty dupes |
| **Screen result** | Scan tab empty until Create/Load/scan |
| **Success** | App usable |
| **Failure** | Same as startup failures |
| **Safeguards** | Prior quotes remain on disk |
| **Missing safeguards** | Users may expect last quote to reopen automatically |
| **Diagnostic tags** | `[QuoteDiag]` startup |
| **Tests** | None |
| **Phone test** | Confirm must **Load Quote** after restart |

---

## 19. Restore state

| Field | Evidence |
|-------|----------|
| **User action** | **Load Quote** or Archive **Restore** |
| **UI handler** | `_showLoadQuoteDialog` / `_onArchiveRestorePressed` |
| **Call sequence** | Load: prune → conditional save → list → `_loadQuoteById`. Restore: conflict check → `_restoreArchivedQuoteToActiveIndex` |
| **State changes** | Workspace load or indexes move archive→active |
| **Files read** | Quote JSON + indexes |
| **Files written** | Both index files on restore; quote file retained |
| **Indexes** | Archive remove + active add on restore |
| **Screen result** | `Quote restored to Active.` or loaded lines |
| **Success** | No customer+bucket conflict |
| **Failure** | Conflict snackbar; restore false |
| **Safeguards** | Conflict detection; archive-only cannot Load Quote |
| **Missing safeguards** | Load Quote dialog list may be stale after email archive until reopened |
| **Diagnostic tags** | `[QuoteArchive]`, `[EmailArchive]` |
| **Tests** | None |
| **Phone test** | Email archive → Restore → Load |

---

## 20. Load an active quote

| Field | Evidence |
|-------|----------|
| **User action** | **Load Quote** → tap quote |
| **UI handler** | `_showLoadQuoteDialog` → `_loadQuoteById(reason: load_quote_dialog_user_selected)` |
| **Call sequence** | Prune; save if id/lines/user-edited name; show dialog; load selection |
| **State changes** | Workspace = selected quote |
| **Files read** | Active index + quote file |
| **Files written** | Pre-open save may write current |
| **Indexes** | Possibly updated by pre-save |
| **Screen result** | Dialog title **Load Quote**; search **Search quotes** |
| **Success** | Selected id loads |
| **Failure** | Empty list → `No saved quotes` |
| **Safeguards** | Avoids minting empty auto-named rows after export |
| **Missing safeguards** | Email from dialog may not refresh dialog list in-place |
| **Diagnostic tags** | `[QuoteDiag]`, `[EmailArchive]` |
| **Tests** | None |
| **Phone test** | Search + load |

---

## 21. Email Current Quote

| Field | Evidence |
|-------|----------|
| **User action** | Load Quote Email → **Email Current Quote Only (moves to Archive)** |
| **UI handler** | `_onLoadQuoteEmailTapped` `current` → `_shareQuoteById(archiveAfterShare: true)` |
| **Call sequence** | Bundle CSV+XLSX → `Share.shareXFiles` → `_archiveActiveQuotesAfterEmailShare` → maybe `_startNewQuote` |
| **State changes** | May clear workspace if emailed id was current |
| **Files read** | `quote_<id>.json` |
| **Files written** | Temp attachments; `quotes_archive.json` add; `quotes_active.json` remove |
| **Indexes** | Active → Archive |
| **Screen result** | OS share sheet; then Archive membership |
| **Success** | Share invoked; move attempted |
| **Failure** | Not active-eligible; share exception |
| **Safeguards** | UI label warns Archive |
| **Missing safeguards** | Archive after share return — cancel behavior **NEEDS PHONE VERIFICATION** |
| **Diagnostic tags** | `[EmailShare]`, `[EmailArchive]`, `[EmailArchive][Move]` |
| **Tests** | None |
| **Phone test** | Required regression R2 |

---

## 22. Email Customer Quotes

| Field | Evidence |
|-------|----------|
| **User action** | **Email All Quotes for This Customer (archives included active quotes)** |
| **UI handler** | `customer` → `_shareMultipleSavedQuotesForEmail(..., archiveAfterShare: true)` |
| **Call sequence** | Filter active index by customer → multi share → archive each bundled id |
| **State changes** | Workspace reset if current archived |
| **Files read** | Multiple quote files |
| **Files written** | Temp attachments; both indexes |
| **Indexes** | Matching actives archived |
| **Screen result** | Share sheet with many attachments |
| **Success** | Attachments non-empty |
| **Failure** | No customer context; empty subset |
| **Safeguards** | Label discloses archive |
| **Missing safeguards** | Same share-cancel uncertainty |
| **Diagnostic tags** | `[EmailShare]`, `[EmailArchive]` |
| **Tests** | None |
| **Phone test** | Required regression R3 |

---

## 23. Email All Saved Quotes

| Field | Evidence |
|-------|----------|
| **User action** | **Email All Saved Quotes (share only — does not archive)** → **Continue** |
| **UI handler** | `all` → `_shareMultipleSavedQuotesForEmail(..., archiveAfterShare: false)` |
| **Call sequence** | Confirm dialog → all active index → share only |
| **State changes** | None to indexes |
| **Files read** | All active quote files |
| **Files written** | Temp attachments only |
| **Indexes** | Unchanged |
| **Screen result** | Share sheet; quotes stay Active |
| **Success** | Share opens |
| **Failure** | Empty index; user cancels Continue |
| **Safeguards** | Explicit “does not archive” copy |
| **Missing safeguards** | Large attachment sets may stress share UI — **NEEDS PHONE VERIFICATION** |
| **Diagnostic tags** | `[EmailShare]` |
| **Tests** | None |
| **Phone test** | Required regression R4 |

---

## 24. Export Current Quote

| Field | Evidence |
|-------|----------|
| **User action** | **Export Current Quote Only** |
| **UI handler** | `_exportCurrentQuoteOnlyToCsv` |
| **Call sequence** | `_saveQuote` → validate active → write CSV → `_moveActiveQuoteToArchiveAfterSuccessfulExport` → `_startNewQuote` if moved → share/success dialog |
| **State changes** | New empty starter after successful archive move |
| **Files read** | Current quote JSON |
| **Files written** | Export CSV under ShowroomExports layout; indexes |
| **Indexes** | Current archived |
| **Screen result** | Success dialog; note about Archive |
| **Success** | File exists; move preferred |
| **Failure** | No customer/lines; empty quote; already archive-only |
| **Safeguards** | Skips empty; refuses non-active |
| **Missing safeguards** | If move fails, CSV still saved but quote may remain Active |
| **Diagnostic tags** | `[ExportCurrent]`, `[OrderExportCurrent]` |
| **Tests** | None |
| **Phone test** | Export → Archive tab |

---

## 25. Export all quotes

| Field | Evidence |
|-------|----------|
| **User action** | **Export All Quotes** / **Export Order (Saved to OneDrive / Share)** |
| **UI handler** | `_exportAllQuotesToCsv` |
| **Call sequence** | Save → newest non-empty active per bucket → CSVs (+ system reports) → archive each → success dialog |
| **State changes** | Exported quotes leave Active |
| **Files read** | Matching quote JSON files |
| **Files written** | Multiple CSVs; indexes |
| **Indexes** | Exported ids archived (`movedToArchiveCount`) |
| **Screen result** | Success with move count |
| **Success** | ≥1 matching bucket quote |
| **Failure** | No customer; no routed quotes |
| **Safeguards** | Skip empty/stale archive duplicates |
| **Missing safeguards** | Partial failure count logged; user must read dialog |
| **Diagnostic tags** | `[ExportAll]`, `[QuoteIndexAudit]`, `[ExportCheck]` |
| **Tests** | None |
| **Phone test** | Multi-bucket customer |

---

## 26. Archive quote

| Field | Evidence |
|-------|----------|
| **User action** | Side effect of email Current/Customer or export Current/All |
| **UI handler** | `_moveActiveQuoteToArchiveAfterSuccessfulExport` |
| **Call sequence** | Parse active → remove id(s) → write archive first → write active; rollback archive if active write fails |
| **State changes** | Quote no longer Load Quote eligible |
| **Files read** | Active/archive indexes |
| **Files written** | `quotes_active.json`, `quotes_archive.json` (quote JSON kept) |
| **Indexes** | Active→Archive |
| **Screen result** | Appears under **Archive** tab |
| **Success** | `[EmailArchive][Move] SUCCESS` |
| **Failure** | Id not in active; write errors |
| **Safeguards** | Archive-before-active-commit with rollback |
| **Missing safeguards** | No standalone Scan-tab Archive button. Empty Archive copy still says *Export a quote from Orders to see it here* even though the Orders tab is hidden from navigation |
| **Diagnostic tags** | `[EmailArchive][Move]` |
| **Tests** | None |
| **Phone test** | After export/email |

---

## 27. Restore archived quote

| Field | Evidence |
|-------|----------|
| **User action** | Archive tab → Restore |
| **UI handler** | `_onArchiveRestorePressed` |
| **Call sequence** | `_findActiveIndexRowConflictingWithRestore` → `_restoreArchivedQuoteToActiveIndex` |
| **State changes** | Index membership only until user Load Quote |
| **Files read** | Archive + active indexes; quote file |
| **Files written** | Both indexes |
| **Indexes** | Archive→Active |
| **Screen result** | `Quote restored to Active.` |
| **Success** | `ok` true |
| **Failure** | Conflict snackbar |
| **Safeguards** | Customer+bucket conflict block |
| **Missing safeguards** | Does not auto-open restored quote into workspace |
| **Diagnostic tags** | `[QuoteArchive]` |
| **Tests** | None |
| **Phone test** | Restore + Load Quote |

---

## 28. Confirm quote

| Field | Evidence |
|-------|----------|
| **User action** | Archive → Confirm |
| **UI handler** | `_onArchiveConfirmPressed` → `_archiveMarkQuoteConfirmed` |
| **Call sequence** | Update archive index status to confirmed |
| **State changes** | Confirmed grouping in Archive UI |
| **Files read** | Archive index |
| **Files written** | `quotes_archive.json` |
| **Indexes** | Archive status field |
| **Screen result** | `Quote marked Confirmed.` |
| **Success** | Update ok |
| **Failure** | Snackbar could not update |
| **Safeguards** | Does not affect Active |
| **Missing safeguards** | Confirm does not export/email |
| **Diagnostic tags** | `[QuoteArchive]` |
| **Tests** | None |
| **Phone test** | Confirm then purge rules |

---

## 29. Delete active quote

| Field | Evidence |
|-------|----------|
| **User action** | Load Quote → delete row |
| **UI handler** | `_removeQuoteFromIndex` |
| **Call sequence** | Delete `quote_<id>.json` → remove active index row → clear workspace if current |
| **State changes** | `Quote deleted`; empty workspace if was current |
| **Files read** | Index + quote file |
| **Files written** | Index rewrite; quote file deleted |
| **Indexes** | Active row removed |
| **Screen result** | Removed from list; workspace cleared when applicable |
| **Success** | Returns true |
| **Failure** | `[QuoteDelete]` snackbar |
| **Safeguards** | Clears `_currentQuoteId` so `_saveQuote` cannot resurrect file |
| **Missing safeguards** | Irreversible without backups |
| **Diagnostic tags** | `[QuoteDelete]`, `[QuoteDiag]` |
| **Tests** | None |
| **Phone test** | Required regression R5 |

---

## 30. Delete archived quote

| Field | Evidence |
|-------|----------|
| **User action** | Archive delete or purge |
| **UI handler** | `_onArchiveDeletePressed` / purge handlers |
| **Call sequence** | `_confirmArchiveDelete` → `_deleteArchivedQuoteById` or `_purgeArchivedQuotesByStatus` |
| **State changes** | Archive list shrinks |
| **Files read** | Archive index / quote files |
| **Files written** | Archive index; quote file deleted when allowed |
| **Indexes** | Archive updated |
| **Screen result** | Confirm dialogs with distinct copy for archived vs confirmed |
| **Success** | Delete/purge counts |
| **Failure** | Logged `[QuoteArchive]` |
| **Safeguards** | Explicit confirm; purge scoped by status |
| **Missing safeguards** | Purge is bulk destructive |
| **Diagnostic tags** | `[QuoteArchive]` |
| **Tests** | None |
| **Phone test** | Single delete + purge |

---

## 31. Import one order file

| Field | Evidence |
|-------|----------|
| **User action** | **Import Order** / **Import Order (OneDrive → Import folder)** |
| **UI handler** | `_pickAndImportOrderCsv` |
| **Call sequence** | Pick file → parse → `_prepareOrderImportLines` → duplicate UI → `_applyOrderImportPrepareOutcome` (MOQ) → `_saveQuote` → summary → maybe ECatalog tab |
| **State changes** | Lines merged into routed bucket quotes |
| **Files read** | Picked CSV/Excel |
| **Files written** | Touched `quote_*.json` + active index; optional without-UPC state |
| **Indexes** | Active upserts for touched quotes |
| **Screen result** | **Import Summary** dialog |
| **Success** | `[ImportOrder] import success` |
| **Failure** | Parse/match errors snackbar |
| **Safeguards** | MOQ rounding; duplicate resolution choices |
| **Missing safeguards** | Large imports may feel hung — **NEEDS PHONE VERIFICATION** |
| **Diagnostic tags** | `[ImportOrder]`, `[ImportPrepare]`, `[ImportApply]`, `[ImportRoute]` |
| **Tests** | None end-to-end |
| **Phone test** | One known CSV |

---

## 32. Import multiple files

| Field | Evidence |
|-------|----------|
| **User action** | Multi-select in file picker |
| **UI handler** | Same import loop over files |
| **Call sequence** | Aggregate prepare/apply; summary lists files |
| **State changes** | Combined into routed quotes |
| **Files read** | Multiple inputs |
| **Files written** | Quote files + indexes |
| **Indexes** | Updated for touched ids |
| **Screen result** | Summary `Files imported: …` |
| **Success** | All files processed |
| **Failure** | Per-file errors logged |
| **Safeguards** | Same as single |
| **Missing safeguards** | Partial success messaging depth varies |
| **Diagnostic tags** | `[ImportOrderFile]`, `[ImportOrder]` |
| **Tests** | None |
| **Phone test** | Two files |

---

## 33. ECatalog search

| Field | Evidence |
|-------|----------|
| **User action** | Type in E-Catalog **Search** |
| **UI handler** | `_onCatalogSearchChanged` → `_filteredCatalogProducts` |
| **Call sequence** | Normalize/compact match on item, description, UPC, type, category |
| **State changes** | `_catalogSearchQuery` |
| **Files read** | None |
| **Files written** | None |
| **Indexes** | None |
| **Screen result** | Filtered list or no-products message |
| **Success** | Matching rows |
| **Failure** | Empty query shows broader filtered set |
| **Safeguards** | Scroll dismisses keyboard |
| **Missing safeguards** | Performance on full catalog — **NEEDS PHONE VERIFICATION** |
| **Diagnostic tags** | — |
| **Tests** | None |
| **Phone test** | Partial description |

---

## 34. ECatalog filter

| Field | Evidence |
|-------|----------|
| **User action** | Chips **New Items**, **Everyday**, **Decor & Giftware**, **Seasonal**, **Sale**, **In Order**, **In Stock Only**, **Previously Ordered Only**, **Clear Filters**; Category/Sub-Category |
| **UI handler** | `_productMatchesEcatalogMerchandising` / `_matchesCatalogBaseFilters` |
| **Call sequence** | Combine merchandising + base filters + search |
| **State changes** | Chip/dropdown selections |
| **Files read** | Walk/history already in memory |
| **Files written** | None |
| **Indexes** | None |
| **Screen result** | Narrowed list |
| **Success** | Expected membership |
| **Failure** | Over-filter to empty |
| **Safeguards** | Seasonal set includes live + legacy Summer types (`kEcatalogSeasonalProductTypes`) |
| **Missing safeguards** | Chip semantics need phone confirmation for edge SKUs |
| **Diagnostic tags** | — |
| **Tests** | Seasonal membership unit tests |
| **Phone test** | R10 Seasonal live Summer |

---

## 35. Add from ECatalog

| Field | Evidence |
|-------|----------|
| **User action** | Row **Add** / search **Add** / qty increment |
| **UI handler** | `_incrementCatalogProductQty` / `_addECatalogSearchEntry` → routing → `_addProduct` |
| **Call sequence** | Requires scannable digits in UPC or item #; customer; `_ensureRoutingForProduct` |
| **State changes** | Order lines |
| **Files read** | None |
| **Files written** | Memory until save |
| **Indexes** | Unchanged until save |
| **Screen result** | Qty in order summary / line |
| **Success** | Added |
| **Failure** | Skip log if no digits; no customer |
| **Safeguards** | Customer gate |
| **Missing safeguards** | Items without digit payload cannot add via this path |
| **Diagnostic tags** | `[ECatalog]` |
| **Tests** | None |
| **Phone test** | Add with filters on |

---

## 36. Camera scan

| Field | Evidence |
|-------|----------|
| **User action** | **Scan with Camera** |
| **UI handler** | `_openCameraScanner` → `_CameraScannerPage.onDetect` → `_processScan` |
| **Call sequence** | `_editDialogOpen=true` → push route → process → overlay qty |
| **State changes** | Same as scan add |
| **Files read** | None |
| **Files written** | Memory until save |
| **Indexes** | None immediate |
| **Screen result** | Camera UI title **Scan with Camera** |
| **Success** | Product returned to overlay |
| **Failure** | Null product; permission issues |
| **Safeguards** | Uses same scan pipeline |
| **Missing safeguards** | Permission UX **NEEDS PHONE VERIFICATION** |
| **Diagnostic tags** | `[ScanLookup]` etc. |
| **Tests** | None |
| **Phone test** | Required |

---

## 37. HID Bluetooth scan

| Field | Evidence |
|-------|----------|
| **User action** | Hardware wedge UPC+Enter |
| **UI handler** | Hidden scanner field → buffer → `_enqueueScan` → `_processScan` |
| **Call sequence** | Focus reclaim timers; 80ms dedupe; queue drain |
| **State changes** | Lines/totals/sounds |
| **Files read** | None |
| **Files written** | Memory until save |
| **Indexes** | None immediate |
| **Screen result** | Line at top; beep |
| **Success** | Item added |
| **Failure** | Lost focus; other tab (Scan subtree not built) |
| **Safeguards** | Focus listeners; tab-return restore; dedupe |
| **Missing safeguards** | Scanning while dialogs open blocked via `_editDialogOpen` |
| **Diagnostic tags** | `[ScannerField][FocusListener]`, `[ScanPerf]` |
| **Tests** | None |
| **Phone test** | Required with paired scanner |

---

## 38. Manual entry

| Field | Evidence |
|-------|----------|
| **User action** | **Item # / UPC** → **Add** |
| **UI handler** | `_addQuickEntry` |
| **Call sequence** | Exact match → `_ensureQuoteReadyForManualAdd` → routing → `_addProduct` → focus restore |
| **State changes** | Line add; clear field |
| **Files read** | None |
| **Files written** | Memory until save |
| **Indexes** | None immediate |
| **Screen result** | Status / quick entry status text |
| **Success** | Exact unique match |
| **Failure** | Not found; ambiguous duplicates return null match |
| **Safeguards** | Invalid path forces scanner focus |
| **Missing safeguards** | Partial matches do not fuzzy-add |
| **Diagnostic tags** | `[ManualEntry][Submit]`, `[ManualEntry][InvalidFocusRestore]` |
| **Tests** | None |
| **Phone test** | Invalid then valid |

---

## 39. Quick Entry

| Field | Evidence |
|-------|----------|
| **User action** | Same as #38 (code name “quick entry”) |
| **UI handler** | `_addQuickEntry` / `_ScanTabItemSearchBlock` |
| **Call sequence** | Identical to manual entry |
| **State changes** | Same as #38 |
| **Files read** | None |
| **Files written** | Memory until save |
| **Indexes** | None immediate |
| **Screen result** | Label is **Item # / UPC**, not “Quick Entry” |
| **Success** | Same as #38 |
| **Failure** | Same as #38 |
| **Safeguards** | Same as #38 |
| **Missing safeguards** | Same as #38 |
| **Diagnostic tags** | `[ManualEntry]*` |
| **Tests** | None |
| **Phone test** | Same as #38 |

---

## 40. Build Full Catalog Quote

| Field | Evidence |
|-------|----------|
| **User action** | Setup → **Build Full Catalog Test Quote** |
| **UI handler** | `_buildFullCatalogTestQuoteFlow` → `_persistFullCatalogTestQuote` |
| **Call sequence** | **`if (!kDebugMode) return`**; picker → confirm → persist all products into one quote |
| **State changes** | Huge quote may load into workspace (debug) |
| **Files read** | In-memory catalog |
| **Files written** | Large `quote_<id>.json` + active index |
| **Indexes** | Active row for test quote |
| **Screen result** | Confirm **Full catalog test quote** |
| **Success** | Persisted |
| **Failure** | No products/customers; cancel; no-op in release |
| **Safeguards** | Debug-only gate; Create Quote empty-starter-only avoids auto-adopting non-empty on fresh create |
| **Missing safeguards** | Dangerous if used mid-showroom; performance risk |
| **Diagnostic tags** | `[DependentsDiag]` |
| **Tests** | None |
| **Phone test** | Debug only; never during live orders |

---

## Cross-cutting archive matrix (code)

| Action | Archives? |
|--------|-----------|
| Email Current Quote Only | Yes (`archiveAfterShare: true`) |
| Email All Quotes for This Customer | Yes |
| Email All Saved Quotes | **No** |
| Export Current Quote Only | Yes |
| Export All Quotes | Yes |
| Share sheet alone without those flags | No |

---

## End of Phase 5 traces
