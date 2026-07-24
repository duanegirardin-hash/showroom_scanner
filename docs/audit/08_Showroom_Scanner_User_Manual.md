# Showroom Scanner — User Manual

Plain-language guide for showroom staff. Button names match the app.  
Baseline documented: commit `320f117` (`pre-full-audit`).

When behavior cannot be proven from code alone: **NEEDS PHONE VERIFICATION**.

---

## WHAT NOT TO DO

- Do not clear the app’s storage unless important quotes have been exported or backed up.
- Do not uninstall the app before protecting important quotes (exports/email).
- Do not use **Build Full Catalog Test Quote** during normal customer-order work.
- Do not assume **Email All Saved Quotes** archives quotes — it does **not**.
- Do not select the wrong customer before scanning.
- Do not ignore incorrect pricing on screen or in exports.
- Do not ignore incorrect Product Type routing (wrong quote name/bucket).
- Do not force-close the app during save, import, export, archive, or email preparation.
- Do not disconnect the phone during installation.
- Do not directly edit bundled JSON or CSV files on the phone.
- Do not delete a quote without confirming it is no longer needed.
- Do not treat a share-sheet cancellation as a confirmed sent email unless you verify Archive/Active afterward. **NEEDS PHONE VERIFICATION**
- Do not assume every operation has cloud backup — quotes live in app storage under `showroom_quotes/`.
- Do not use developer/Setup tools casually (**LOAD PRODUCTS**, walk-order editor, full-catalog tools).

---

## 1. What the app does

Showroom Scanner builds customer quotes by scanning barcodes (Bluetooth or camera), typing item numbers, browsing **E-Catalog**, importing order files, and exporting or emailing quotes. Different Product Types automatically go into separate quotes (for example Everyday vs Halloween vs Summer Toys).

## 2. Important safety information

Quotes are stored on the phone. Email/export moves some quotes to **Archive**. Clearing app data or uninstalling can destroy unsaved or unexported work.

## 3. Starting the app

Open **Showroom Scanner**. The app locks to portrait. It loads customers, then products (Google Sheet when online, otherwise built-in catalog). Wait until status is ready to scan. **NEEDS PHONE VERIFICATION** for exact on-screen timing.

## 4. Selecting a customer

Use the customer picker (search by name/contact/email). You must select a customer before adding items. Message if missing: **Please select a customer first.**

## 5. Creating a quote

Tap **Create Quote**. If no customer is selected, pick one first. Confirm in the **Create Quote** dialog. If the current order has items, they are saved first, then a new empty quote starts. Create Quote is designed as an empty starter and will not pull in a huge existing catalog quote. (**R1**)

## 6. Understanding automatic quote separation

Each product has a Product Type. The app maps that type to a quote “bucket” (Everyday, Christmas, Summer General, Summer Toys, and others). Scanning a different type saves the current quote and opens or creates the matching quote.

## 7. Everyday quotes

Everyday / default items go to the Everyday quote (`every_day`). New Everyday quotes are often named like **EVERYDAY QUOTE_…**.

## 8. Seasonal quotes

Seasonal Product Types (Halloween, Harvest, Mother’s Day, Christmas, etc.) each get their own quote when mapped in configuration.

## 9. Summer General

Live sheet type **SPRING/SUMMER - GENERAL** and legacy **SUMMER GENERAL** both route to **SUMMER GENERAL** (same bucket). They stay separate from Toys.

## 10. Summer Toys

**SPRING/SUMMER - TOYS** and **SUMMER TOYS** route to **SUMMER TOYS**, separate from Summer General.

## 11. Switching quotes

Automatic: scan a different Product Type. Manual: tap **Load Quote**, search, tap a saved active quote.

## 12. Scanning with Bluetooth

Pair the scanner as a keyboard. Keep the Scan tab active so the hidden scan field can take focus. Scan UPC; the app adds the item (quantity starts at Minimum Order Quantity).

## 13. Scanning with camera

Tap **Scan with Camera**. Allow camera permission if asked. **NEEDS PHONE VERIFICATION** Point at the barcode; successful scans add like Bluetooth.

## 14. Manual item entry

On Scan, use **Item # / UPC**, type an exact item number or UPC, tap **Add**.

## 15. Quick Entry

Same control as manual entry (**Item # / UPC** + **Add**). There is no separate button labeled “Quick Entry.”

## 16. Understanding product cards

Order lines show description, item number, quantities, prices, and availability summaries. Expand a row for more detail. **NEEDS PHONE VERIFICATION** for exact card layout on your phone size.

## 17. Item numbers

Catalog key used for search, images, and matching imports.

## 18. UPCs

Barcodes usually scan as digits. Missing/invalid UPC scans show **UPC / ITEM NOT FOUND**.

## 19. Descriptions

Product name text on cards and exports.

## 20. Prices

Shelf/sale **Price** on the product drives order pricing rules; **List Price** is also stored and used in email/export columns separately.

## 21. Regular price

Non-PS, non-NET items without special handling use regular shelf price (customer discount may still apply when eligible).

## 22. Customer-discount price

If the customer has a discount percent and the item is discount-eligible, the unit price is reduced. PS/NET rules override discount application.

## 23. PS price

Items flagged PS use PS pricing rules; PS takes precedence when both PS and NET are set.

## 24. NET price

Items flagged NET use NET rules when not PS.

## 25. MOQ

Minimum Order Quantity. First add and +/- steps use MOQ. Imports round quantities to valid MOQ multiples.

## 26. Case quantity

Shown from catalog (`Case Quantity`). Used for information/export; stepping uses MOQ, not case qty.

## 27. Availability

Warehouse 1 and Warehouse 2 availability text appears on product detail surfaces.

## 28. Increasing quantity

Use **+** on a line (adds MOQ) or **Edit Quantity**.

## 29. Decreasing quantity

Use **−**. If quantity would fall below 1, the line is removed.

## 30. Deleting an item

Use delete on the line; confirm **Delete Item** → **Delete**.

## 31. Repeated scans

Scanning an item already on the quote increases quantity by MOQ and moves it to the top. Very fast duplicate scans within ~80ms may be ignored.

## 32. Invalid scans

Empty/non-digit payloads are ignored. Unknown codes show not found and play an error sound.

## 33. Item not found

Status **UPC / ITEM NOT FOUND** / **NOT FOUND**. Check catalog refresh and UPC.

## 34. Product images

Loaded from `https://showroom-images.netlify.app/images/{itemNumber}.jpeg`. Missing images should not crash the app. **NEEDS PHONE VERIFICATION**

## 35. ECatalog

Tab **E-Catalog** browses the loaded catalog with search, filters, and **Add**.

## 36. Searching

**Search** hint: Item #, description, UPC, type, category. Tap **Add** beside search to add an exact match when possible.

## 37. Category filters

**Category** dropdown narrows the list.

## 38. Sub-category filters

**Sub-Category** dropdown (depends on category).

## 39. Product Type filters

Merchandising chips include **Everyday**, **Seasonal**, **Decor & Giftware**, **New Items**, **Sale**, plus stock/order chips.

## 40. Seasonal filter

**Seasonal** includes configured seasonal Product Types, including both live Spring/Summer labels and legacy Summer labels.

## 41. New Release filter

**New Items** chip filters new-release products.

## 42. Sale filter

**Sale** chip filters sale-priced / sale-indicated items per catalog flags.

## 43. In Stock filter

**In Stock Only** limits to in-stock rules used by ECatalog.

## 44. In Order filter

**In Order** limits to the selected customer’s walk-order items when walk data exists.

## 45. Customer walk order

Walk positions come from bundled `customer_walk_order.csv`. Setup → **Walk Order Editor** can review/export (**Export Walk Order CSV**).

## 46. Previously Ordered Only

**Previously Ordered Only** shows items found in that customer’s archived/order history used by the app.

## 47. Never Add

Walk rows marked Never Add appear as **Never Add** for guidance; follow showroom policy before adding.

## 48. Importing orders

On E-Catalog: **Import Order**. On order panel: **Import Order (OneDrive → Import folder)**. Pick CSV/Excel from the phone. Review duplicate prompts and **Import Summary**.

## 49. Exporting current quote

**Export Current Quote Only**. Saves CSV, moves that quote to **Archive**, starts a new empty quote for the same customer when archive move succeeds.

## 50. Exporting all

**Export All Quotes** (and related **Export Order (Saved to OneDrive / Share)** on the orders UI). Exports each active bucket quote for the customer and archives exported quotes.

## 51. Email Current Quote

From **Load Quote** → Email → **Email Current Quote Only (moves to Archive)**. Opens the share sheet with CSV/XLSX, then archives.

## 52. Email Customer Quotes

**Email All Quotes for This Customer (archives included active quotes)**.

## 53. Email All Saved Quotes

**Email All Saved Quotes (share only — does not archive)** after **Continue**. Shares all customers’ active saved quotes without archiving.

## 54. What gets archived

Email Current, Email Customer, Export Current, Export All (successful moves).

## 55. What does not get archived

**Email All Saved Quotes**; ordinary scanning; Create Quote; Load Quote without email/export.

## 56. Active quotes

Editable quotes listed in **Load Quote** and stored in `quotes_active.json`.

## 57. Archived quotes

**Archive** tab. View read-only, restore, confirm, re-export, or delete. Quotes arrive here after export or Email Current/Customer (not Email All). If the empty state mentions exporting from “Orders,” use the **E-Catalog** export buttons instead — the Orders tab is not shown in the current tab bar.

## 58. Confirmed quotes

Archive → **Confirm** marks a quote confirmed. Purge confirmed is a separate Setup/Archive action.

## 59. Restoring a quote

Archive → Restore. Fails if an active quote already exists for the same customer and bucket.

## 60. Confirming a quote

Archive → Confirm → snackbar **Quote marked Confirmed.**

## 61. Deleting a quote

Active: from Load Quote delete (clears workspace if it was open). Archived: delete/purge with confirmation dialogs.

## 62. Closing and reopening

Backgrounding tries to save the working quote. Reopening does **not** automatically put the last quote on screen — use **Load Quote**. **NEEDS PHONE VERIFICATION** for force-stop.

## 63. Persistence

On-device folder `showroom_quotes/` with `quotes_active.json`, `quotes_archive.json`, and `quote_<id>.json`. Local added customers: `added_customers.json`.

## 64. Setup tools

Tab **Setup** / **Data / Setup**: **LOAD PRODUCTS**, **LOAD CUSTOMERS**, **Add Customer**, **Walk Order Editor**, plus debug catalog tools when present.

## 65. Build Full Catalog Quote

Button **Build Full Catalog Test Quote** (debug builds). Creates one huge test quote. **Do not use during live selling.** Release builds skip this flow.

## 66. Troubleshooting

See `10_Showroom_Scanner_Troubleshooting.md`.

## 67. Backups

Export or email important quotes before clearing data, switching phones, or uninstalling. There is no automatic cloud backup inside the app.

## 68. Glossary

See `11_Showroom_Scanner_Glossary.md`.

---

*End of user manual*
