# 04 — Data and Configuration Audit

| Field | Value |
|-------|--------|
| Baseline | `320f117` / `pre-full-audit` |
| Rule | No data files modified |

---

## 1. Product Types — CSV vs JSON vs ECatalog

### 1.1 Bundled catalog Product Types

From `assets/data/products.csv` (~17,864 data rows), unique Product Types observed:

| Approx count | Product Type |
|-------------:|--------------|
| ~10383 | EVERYDAY |
| ~2236 | CHRISTMAS |
| ~1394 | SUMMER GENERAL |
| ~794 | HALLOWEEN |
| ~596 | GIFTCRAFT |
| ~535 | EASTER |
| ~438 | SUMMER TOYS |
| ~357 | VALENTINE'S DAY |
| ~325 | FALL/WINTER ESSENTIALS |
| ~229 | HARVEST |
| ~215 | KSP |
| ~130 | CANADA DAY |
| ~45 | ST PATRICK'S DAY |
| ~39 | FIFA |
| ~36 | MOTHER'S DAY |
| ~29 | NEW YEARS |
| ~27 | PRIDE |
| ~15 | FATHER'S DAY |
| ~12 | GRADUATION |
| ~11 | CALENDAR |
| ~9 | HANUKKAH |
| ~7 | DIWALI |
| ~2 | CHINESE NEW YEAR |

**Not present as Product Type in bundled CSV:** `SPRING/SUMMER - GENERAL`, `SPRING/SUMMER - TOYS` (aliases only in JSON + ECatalog seasonal set for live-sheet compatibility).

### 1.2 Bucket JSON aliases

| Alias pair | Shared bucketKey | Display |
|------------|------------------|---------|
| SUMMER GENERAL + SPRING/SUMMER - GENERAL | summer_general | SUMMER GENERAL |
| SUMMER TOYS + SPRING/SUMMER - TOYS | summer_toys | SUMMER TOYS |
| ST PATRICKS DAY + ST PATRICK'S DAY | st_patricks_day | dual display labels |

### 1.3 Alignment (bundled CSV types)

| CSV Product Type | In JSON? | In ECatalog Seasonal? |
|------------------|----------|------------------------|
| EVERYDAY | Yes | No (by design) |
| GIFTCRAFT | Yes | No |
| KSP | Yes | No |
| FIFA | Yes | No |
| All other mapped seasonals + summers | Yes | Yes (seasonals + both summer naming schemes) |

**JSON-only forward aliases:** SPRING/SUMMER - *.  
**Unmapped live types:** Would fall through to Category then Everyday — **ops risk**.

### 1.4 Category fallback

Routing may map Category when Product Type misses. Category strings (e.g. `Spring/Summer - General`) are not identical to Product Type keys; only normalized hits against JSON raw keys succeed.

**NEEDS PHONE VERIFICATION:** live Google Sheet Product Type strings after LOAD PRODUCTS.

---

## 2. CSV / JSON headers

### Products (expected)

`Item Number`, `Description`, `UPC`, `List Price`, `Price`, `DISCOUNT`, `NET`, `PS`, `New Release`, `Whse 1 Availability`, `Whse 2 Availability`, `Product Type`, `Category`, `Sub-Category`, `Minimum Order Quantity`, `Case Quantity`

### Customers

`Id`, `CompanyName`, `Address`, `Address2`, `City`, `State`, `Zip`, `Phone`, `Fax`, `Email`, `Contact`, `SalesRepName`, `PriceList`, `Discount`, `PaymentTerms`

### Customer walk order

`CustomerID `, `Item Number`, `Description`, `Category`, `Sub-Category`, `WalkPosition`, `SubPosition`, `NeverAdd`, `NeverAddReason`, `WalkEnabled`  
(Note: header may include trailing space on CustomerID.)

### Product type buckets JSON

```json
{ "mappings": { "<RAW TYPE>": { "bucketKey": "...", "displayLabel": "..." } } }
```

---

## 3. Duplicate / identity issues

| Issue | Risk |
|-------|------|
| `products.csv` vs Windows `Products.csv` display | Case-sensitive asset miss |
| St Patrick dual JSON keys | OK (intentional) |
| Summer dual labels | OK; display forced to SUMMER * |
| Blank UPCs / duplicate UPCs | Lookup maps may keep one winner — verify on phone / data ops |
| Blank Product Types | Category fallback or Everyday |
| Invalid prices | Tend toward 0 / non-sale |

Data files were **not** modified to “fix” duplicates.

---

## 4. Google Sheet URLs / gids

| Constant | Spreadsheet id | gid |
|----------|----------------|-----|
| `_productsCsvUrl` | `1UWduf2UklzxcnCA4dd6eKJN8QJb5gWm17k8F70fx1u8` | `1691211520` |
| `_customersCsvUrl` | `1C9KzyNN7P7YVYvjpuCizXtxDdpfsp20UKewBAtStdCg` | `1371098168` |

Format: public CSV export. Auth: none (link must remain readable).  
Local adds: `added_customers.json` — **not** written back to Sheets.

**NEEDS PHONE VERIFICATION / ops:** HTTP 200 + header match.

---

## 5. Image host

`https://showroom-images.netlify.app/images/{itemNumber}.jpeg`

**NEEDS PHONE VERIFICATION:** hit rate for real item numbers.

---

## 6. Android permissions and Gradle

| Permission | Notes |
|------------|-------|
| CAMERA | Camera scanner |
| INTERNET | Sheets + images |
| WRITE_EXTERNAL_STORAGE | maxSdk 28 — legacy public Documents |

| Gradle | Value |
|--------|-------|
| namespace / applicationId | `com.example.showroom_scanner` |
| release signing | **debug** |
| Java/Kotlin | 17 |

Method channel: `com.example.showroom_scanner/documents` (`savePublicCsv`, `savePublicCsvInShowroomExports`).

---

## 7. pubspec assets

Declared and present:

- `assets/data/products.csv`
- `assets/data/customers.csv`
- `assets/data/customer_walk_order.csv`
- `assets/data/product_type_buckets.json`
- `assets/sounds/good_scan.mp3`, `good_scan2.mp3`, `error_scan.mp3`

`flutter_lints` **not** in `pubspec.yaml` despite `analysis_options.yaml` include.

---

## 8. Residual data risks

1. Live Sheet Product Types absent from JSON → Everyday routing.  
2. SPRING aliases unused by bundled CSV but required for live parity — keep tests.  
3. Public Sheet export URLs are single point of failure / access-control boundary.  
4. Asset casing landmine off Windows.  
5. Example package id + debug signing block production readiness.

**No data or configuration files were modified by this audit.**
