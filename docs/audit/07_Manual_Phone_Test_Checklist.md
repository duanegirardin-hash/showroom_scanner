# 07 — Manual Phone Test Checklist

**Audience:** Non-technical showroom user  
**Baseline:** `320f117` / `pre-full-audit`  
**Device target:** Android phone with Bluetooth scanner when noted  
**How to use:** For each test, fill Pass / Fail / Notes. Mark Cursor connection when logs are needed.

**Legend**

| Column | Meaning |
|--------|---------|
| Cursor? | Phone must be connected to Cursor/`flutter run` for log capture |
| Logs? | Capture debug console lines |
| Tag | Grep-friendly diagnostic prefix |

---

## Special regressions (run first)

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | Pass/Fail/Notes |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-----------------|
| R1 | Create Quote must not load huge catalog quote | Debug build with a prior full-catalog test quote on disk for same customer Everyday | Select customer → **Create Quote** → confirm | Everyday / full catalog | Empty new quote; few or zero lines | Huge catalog appears in workspace | Yes | Yes | `[QuoteDiag]` `empty_starter` | |
| R2 | Email Current archives after share | Active quote with lines | **Load Quote** → Email → **Email Current Quote Only (moves to Archive)** → complete/cancel share as instructed by tester | Any | Quote leaves Active; appears in Archive tab (verify both) | Stays Active only | Yes | Yes | `[EmailArchive]` | |
| R3 | Email Customer archives applicable | Customer with ≥2 active bucket quotes | Email → **Email All Quotes for This Customer…** | Multi-bucket | Those active quotes archived | Some remain Active unexpectedly | Yes | Yes | `[EmailArchive]` | |
| R4 | Email All does **not** archive | Several active quotes | Email → **Email All Saved Quotes…** → **Continue** | Mixed | Quotes remain Active | Quotes move to Archive | Yes | Yes | `[EmailShare]` | |
| R5 | Delete active clears workspace | Loaded active quote | Load Quote → delete that quote | Any | Workspace clears; status Quote deleted; cannot scan into deleted id | Lines remain / save resurrects file | Yes | Yes | `[QuoteDelete]` | |
| R6 | Spring/Summer General → Summer General | Catalog item Product Type `SPRING/SUMMER - GENERAL` | Create Quote → scan/add item | Summer General | Quote label/bucket Summer General | Goes to Toys or Everyday | Yes | Yes | `[SummerRouteDiag]` | |
| R7 | Spring/Summer Toys → Summer Toys | Item `SPRING/SUMMER - TOYS` | Scan/add | Summer Toys | Separate Summer Toys quote | Merges into General | Yes | Yes | `[SummerRouteDiag]` | |
| R8 | Two Summer quotes stay separate | One General + one Toys item | Scan both | Both | Two Load Quote rows | Single combined quote | Yes | Yes | `[SummerRouteDiag]` | |
| R9 | Halloween / Harvest / Mother’s Day / Everyday unchanged | One item each | Scan each | Seasonal + Everyday | Separate expected buckets | Wrong bucket | Yes | Optional | `[Routing]` | |
| R10 | ECatalog Seasonal includes live Summer types | E-Catalog tab | Tap **Seasonal**; search known live summer SKUs | SPRING/SUMMER - * | Items visible under Seasonal | Missing | No | Optional | — | |

---

## A. Installation

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| A1 | Install / run build | Phone charged | Install APK or `flutter run`; open Showroom Scanner | — | App opens to Scan | Crash / blank | If flutter | Optional | — | |
| A2 | Orientation | App open | Rotate device | — | Stays portrait | Landscape UI | No | No | — | |

## B. Startup

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| B1 | Cold start online | Wi-Fi on | Force-stop → open | — | Ready to scan; customers available | Stuck loading | Yes | Yes | `[Products]` `[Customers]` | |
| B2 | Cold start offline | Airplane mode | Open | — | Falls back to built-in products | No products | Yes | Yes | `[Products]` | |
| B3 | No auto last quote | Had quote yesterday | Open app | — | Empty until Load Quote | Old lines appear alone | No | No | — | |

## C. Customer selection

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| C1 | Search select | Customers loaded | Open picker; search name; select | Known customer | Name shows as selected | Wrong customer | No | No | — | |
| C2 | Scan without customer | No customer | Scan barcode | Any | Snackbar Please select a customer first | Line adds anyway | No | No | — | |

## D. Create Quote

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| D1 | Create with picker | No customer | **Create Quote** → pick → confirm | — | Empty Everyday-named starter | Cancel leaves prior state | Yes | Yes | `[QuoteDiag]` | |
| D2 | Create saves prior | Quote with lines | **Create Quote** → confirm | — | Prior saved; new empty | Prior lost | Yes | Yes | `[QuoteDiag]` | |

## E. Active quotes

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| E1 | Load Quote list | ≥1 saved active | **Load Quote** | — | List shows actives | Missing / archive mixed in | No | Optional | — | |
| E2 | Switch via Load | Two actives | Load each | — | Lines/name/customer match | Wrong data | No | No | — | |

## F. Bluetooth scanning

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| F1 | Good scan | Customer + Create Quote | Scan valid UPC | In-catalog | Beep; line added | No add | Yes | Yes | `[ScanLookup]` | |
| F2 | Double scan | Same as F1 | Scan same UPC twice quickly | Same | Qty increases by MOQ (after dedupe window) | Duplicate beeps only | Yes | Yes | `[ScanPerf]` | |
| F3 | Focus after Add | After manual Add | Scan again | — | Scan captured | Keystrokes in wrong field | Yes | Yes | `[ScannerField]` | |

## G. Camera scanning

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| G1 | Camera add | Permissions allow | **Scan with Camera**; point at barcode | Valid UPC | Item adds; overlay qty | Permission denied / no detect | Yes | Optional | — | |

## H. Manual entry

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| H1 | Exact item # | Customer selected | Type Item # in **Item # / UPC** → **Add** | Exact SKU | Added | Not found | Yes | Yes | `[ManualEntry]` | |
| H2 | Invalid | Same | Type junk → **Add** | — | Not found; focus returns | Stuck keyboard focus | Yes | Yes | `[ManualEntry][InvalidFocusRestore]` | |

## I. Quick Entry

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| I1 | Same control as H | — | Use **Item # / UPC** + **Add** | — | Same as H1 | — | No | Optional | `[ManualEntry]` | |

## J. Product Type routing

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| J1 | Auto split | Empty Everyday | Scan Everyday then Halloween | Both | Two quotes | One merged | Yes | Yes | `[Routing]` | |

## K. Everyday

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| K1 | Everyday route | Create Quote | Scan Everyday item | Everyday | EVERYDAY quote | Seasonal bucket | Optional | Optional | `[Routing]` | |

## L. Summer General

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| L1 | Live General | — | Add `SPRING/SUMMER - GENERAL` | Summer General | Bucket Summer General | Toys/Everyday | Yes | Yes | `[SummerRouteDiag]` | |
| L2 | Legacy General | — | Add `SUMMER GENERAL` if present | Same bucket | Same as L1 | Split wrongly | Yes | Yes | `[SummerRouteDiag]` | |

## M. Summer Toys

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| M1 | Live Toys | — | Add `SPRING/SUMMER - TOYS` | Summer Toys | Separate Toys quote | Merged with General | Yes | Yes | `[SummerRouteDiag]` | |

## N. Other seasonal types

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| N1 | Halloween | — | Scan Halloween | Halloween | Own quote | Everyday | Optional | Optional | `[Routing]` | |
| N2 | Harvest | — | Scan Harvest | Harvest | Own quote | Halloween | Optional | Optional | `[Routing]` | |
| N3 | Mother’s Day | — | Scan Mother’s Day | mothers_day | Own quote | Wrong | Optional | Optional | `[Routing]` | |

## O. Quantities

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| O1 | Plus/minus | Line on order | Tap + / − | MOQ step | Qty changes by MOQ | Wrong step | No | No | — | |
| O2 | Edit dialog | Line | Edit Quantity → Save | — | Exact qty | Rejects 0 | No | No | — | |

## P. MOQ

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| P1 | First add uses MOQ | — | First scan | MOQ>1 item | Qty = MOQ | Qty=1 always | No | No | — | |
| P2 | Import MOQ round | Import file | Import odd qty | MOQ item | Summary shows MOQ Adjustments | Wrong qty | Yes | Yes | `[ImportPrepare]` | |

## Q. Case quantity

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| Q1 | Display | Product detail / card | Open item | Case Qty field | Shows case qty from catalog | Blank wrongly | No | No | — | |

## R. Pricing

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| R-P1 | Discount customer | Discount% customer | Add discount-eligible item | Eligible | Customer price reflects discount | Full list wrongly | No | Optional | `[ECatalog price]` | |
| R-P2 | PS precedence | PS+NET item | View price / export | PS item | PS wins over NET | NET wins | No | Optional | — | |

## S. Availability

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| S1 | Whse lines | Detail | Open product | — | Whse 1 / Whse 2 lines show | Missing | No | No | — | |

## T. Product images

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| T1 | Image load | Online | Open ECatalog row with image | Known item # | Image from netlify URL | Broken icon only | No | No | — | |
| T2 | Missing image | — | Item without hosted jpeg | — | Placeholder / error widget, app stable | Crash | No | No | — | |

## U. ECatalog

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| U1 | Open tab | — | Tap **E-Catalog** | — | Catalog list | Blank forever | No | No | — | |
| U2 | Search Add | — | Search exact → **Add** | Exact | Adds to quote | Skip no digits | Yes | Optional | `[ECatalog]` | |

## V. ECatalog filters

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| V1 | Chips | — | Exercise each chip + **Clear Filters** | — | List narrows/resets | Stuck filter | No | No | — | |
| V2 | Category dropdowns | — | Category + Sub-Category | — | Filtered | Empty wrong | No | No | — | |

## W. Walk order

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| W1 | In Order chip | Customer with walk CSV | **In Order** | Walk customer | Only walk items | All products | No | Optional | `[WalkOrder]` | |
| W2 | Editor | Setup | **Walk Order Editor** → **Export Walk Order CSV** | — | CSV shares/saves | Crash | No | Optional | — | |

## X. Previously Ordered Only

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| X1 | Filter | Customer with archive history | **Previously Ordered Only** | — | Only prior items | Empty wrongly | No | Optional | — | |

## Y. Never Add

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| Y1 | Badge/behavior | Walk NeverAdd YES | View in walk/ECatalog paths | NeverAdd item | Marked Never Add; follow product rules | Ignored | No | Optional | `[WalkOrder]` | |

## Z. Import

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| Z1 | One file | Customer selected | **Import Order** pick CSV | Known rows | Import Summary; lines present | All not found | Yes | Yes | `[ImportOrder]` | |
| Z2 | Multi file | — | Pick 2 files | — | Combined summary | Only first applied | Yes | Yes | `[ImportOrder]` | |

## AA. Export

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AA1 | Current | Active with lines | **Export Current Quote Only** | — | CSV saved; quote Archive; new starter | Still editable same id | Yes | Yes | `[ExportCurrent]` | |
| AA2 | All | Multi bucket | **Export All Quotes** | — | Multiple CSVs; archived | Missing buckets | Yes | Yes | `[ExportAll]` | |

## AB. Email

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AB1–AB3 | See R2–R4 | — | — | — | — | — | — | — | — | |

## AC. Archive

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AC1 | View | After export | **Archive** tab | — | Exported quotes listed | Missing | No | No | — | |
| AC2 | Re-export | Archived | Re-export action | — | CSV produced | Empty error | No | Optional | `[QuoteArchive]` | |

## AD. Confirmed quotes

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AD1 | Mark confirmed | Archived | Confirm | — | Confirmed section/status | Still plain archived | No | No | `[QuoteArchive]` | |

## AE. Delete and restore

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AE1 | Restore | Archived | Restore | — | Back in Active / Load Quote | Conflict snackbar if active exists | No | Optional | `[QuoteArchive]` | |
| AE2 | Delete archive | Archived | Delete confirm | — | Gone from Archive | Still listed | No | Optional | `[QuoteArchive]` | |

## AF. Persistence

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AF1 | Background save | Quote with lines | Home button → wait → reopen → **Load Quote** | — | Lines present | Empty quote | Yes | Yes | `[PersistWorkingQuote]` | |

## AG. Closing/reopening

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AG1 | Soft close | — | Background + reopen | — | App starts; load quote manually | Data gone from disk | No | Optional | — | |
| AG2 | Force stop | — | Force stop mid-edit without background | — | **NEEDS PHONE VERIFICATION** of loss | — | Yes | Yes | — | |

## AH. Background/resume

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AH1 | Focus resume | Scan tab | Background → resume → scan | — | Scanner accepts input | Lost focus | Yes | Yes | `[ScannerField]` | |

## AI. Error handling

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AI1 | Not found scan | — | Scan unknown UPC | — | NOT FOUND + buzz | Silent fail | No | Optional | `[ScanLookup]` | |
| AI2 | Products refresh fail | Offline | Setup **LOAD PRODUCTS** | — | Error snackbar | Crash | No | Optional | `[Products]` | |

## AJ. Performance

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AJ1 | ECatalog scroll | Full catalog | Scroll E-Catalog | — | Usable | Severe jank | No | Optional | — | |
| AJ2 | Large quote load | Big quote | Load Quote | — | Loads eventually | ANR / freeze | Yes | Optional | `[QuoteDiag]` | |

## AK. Full Catalog Quote tool

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AK1 | Debug only | Debug build | Setup **Build Full Catalog Test Quote** | — | Confirm → huge quote saved | Runs in release unexpectedly | Yes | Yes | `[DependentsDiag]` | |
| AK2 | Not for showroom | — | Do **not** run during live orders | — | Tool unused | Accidental huge quote | No | No | — | |

## AL. Release build

| # | Purpose | Start | Steps | Sample | Expected | Failure | Cursor? | Logs? | Tag | P/F/N |
|---|---------|-------|-------|--------|----------|---------|---------|-------|-----|-------|
| AL1 | Release APK | Release build | Open Setup | — | Full catalog test buttons absent/no-op | Tools enabled | No | No | — | |
| AL2 | Core path | Release | Create → scan → export | — | Works without debug tools | Broken | No | Optional | — | |

---

**Tester sign-off**

| Field | Value |
|-------|--------|
| Tester | |
| Phone model | |
| Date | |
| Build / commit | `320f117` |
| Notes | |
