# Showroom Scanner — Troubleshooting

Baseline: `320f117` / `pre-full-audit`. Exact button names from the app.

| Symptom | What to try | Logs / tags | Notes |
|---------|-------------|-------------|-------|
| **App will not start** | Reboot phone; reinstall from known good build; confirm storage not full | Flutter run logs | **NEEDS PHONE VERIFICATION** for device-specific crashes |
| **Products will not load** | Check Wi-Fi; Setup → **LOAD PRODUCTS**; if offline, restart so built-in catalog can load | `[Products]`, `[Products][Verify]` | Sheet gid `1691211520` |
| **Scanner does not type** | Reseat Bluetooth; ensure keyboard mode; open **Scan** tab; wait after keyboard closes | `[ScannerField][FocusListener]` | Hidden field must have focus |
| **Scanner types but does not add** | Select customer; confirm Ready to scan; try **Item # / UPC** + **Add** for same code | `[ScanLookup]` | Not-found vs no-customer |
| **Camera does not scan** | Grant camera permission; good lighting; tap **Scan with Camera** again | — | **NEEDS PHONE VERIFICATION** |
| **Wrong customer selected** | Stop scanning; pick correct customer; **Load Quote** for that customer’s quotes | — | Lines already scanned stay on prior customer’s quotes |
| **Item not found** | Verify barcode; Setup **LOAD PRODUCTS**; try item # manually | `[ScanLookup]` | Status **UPC / ITEM NOT FOUND** |
| **Wrong Product Type quote** | Check product’s Product Type in E-Catalog detail; Summer General vs Toys are separate | `[SummerRouteDiag]`, `[Routing]` | Unmapped types fall back to Everyday |
| **Wrong price** | Check PS / NET / discount eligibility / customer discount %; refresh products | `[ECatalog price]` | PS overrides NET |
| **Quote missing** | **Load Quote** (Active only); check **Archive** after email/export | `[EmailArchive]`, `[ExportCurrent]` | Cold start does not auto-open last quote |
| **Quote appears in wrong section** | Active vs Archive vs Confirmed; restore only if no conflicting active bucket | `[QuoteArchive]` | |
| **Archive empty text mentions Orders** | Use **Export Current Quote Only** / **Export All Quotes** on **E-Catalog** (or email from **Load Quote**) | — | Orders tab UI exists in code but is hidden; empty Archive string still says “from Orders” |
| **Email did not open** | Retry from Load Quote Email menu; ensure quote still Active | `[EmailShare]` | Share sheet is OS-provided |
| **Email did not archive** | Confirm which email option used — **Email All Saved Quotes** never archives; Current/Customer should | `[EmailArchive]` | Cancelled share: **NEEDS PHONE VERIFICATION** whether archive still runs |
| **Export failed** | Select customer; ensure quote has lines; free storage; retry | `[ExportCurrent]`, `[ExportAll]`, `[ExportDiag]` | Empty quotes skipped |
| **Image missing** | Check network; confirm item number; expect netlify jpeg URL | — | Missing image should not block ordering |
| **App seems slow** | Avoid full-catalog test quote; clear filters; fewer huge quotes open | `[ScanPerf]` | Large ECatalog lists are heavy |
| **Huge quote loads** | Do not use **Build Full Catalog Test Quote** in showroom; Create Quote should stay empty | `[QuoteDiag]` `empty_starter` | Delete/archive test quotes in Setup/Archive workflows |
| **Phone disconnects from Flutter** | Replug USB; `flutter devices`; restart adb | — | App on phone may keep running |
| **Lost connection to device** | Same as above; use release APK for floor use without cable | — | |
| **Reinstall versus flutter run** | Reinstall wipes app storage unless backed up; `flutter run` debug ≠ Play release | — | Export first |
| **When logs are needed** | Connect to Cursor/`flutter run`; reproduce; filter tags below | See tag list | |

## Useful diagnostic tags

`[QuoteDiag]` `[EmailShare]` `[EmailArchive]` `[EmailArchive][Move]` `[ExportCurrent]` `[ExportAll]` `[ImportOrder]` `[ScanLookup]` `[ScannerField]` `[ManualEntry]` `[SummerRouteDiag]` `[Routing]` `[Products]` `[Customers]` `[WalkOrder]` `[PersistWorkingQuote]` `[QuoteDelete]` `[QuoteArchive]` `[DependentsDiag]`

## Persistence reminder

Quotes: app documents → `showroom_quotes/` → `quotes_active.json`, `quotes_archive.json`, `quote_<id>.json`.

Images: `https://showroom-images.netlify.app/images/{itemNumber}.jpeg`

Products sheet gid=`1691211520` · Customers gid=`1371098168`
