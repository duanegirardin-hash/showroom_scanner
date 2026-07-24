# Showroom Scanner — Glossary

Terms for showroom users. Matches app labels and on-phone storage where relevant.

| Term | Meaning |
|------|---------|
| **Active quote** | A quote you can still edit; listed under **Load Quote**; indexed in `quotes_active.json`. |
| **Archive** | Tab and storage for quotes moved after export/email (Current/Customer). Indexed in `quotes_archive.json`. |
| **Add** | Button that adds the typed or selected catalog item to the current quote. |
| **Bucket / quote bucket** | Internal grouping for Product Types (Everyday, Summer Toys, Halloween, …). |
| **Build Full Catalog Test Quote** | Debug Setup tool that builds one huge quote of all products — not for live selling. |
| **Case Quantity** | Catalog pack size shown on products; quantity buttons use MOQ, not case qty. |
| **Clear Filters** | E-Catalog control that resets merchandising chips/filters. |
| **Confirmed** | Archive status after you mark a quote confirmed. |
| **Create Quote** | Starts a new empty quote (saves the current one first if it has items). |
| **Customer** | Buyer record (name, id, discount, etc.). Required before adding order lines. |
| **Decor & Giftware** | E-Catalog merchandising chip for that category. |
| **DISCOUNT** | Export/email column for customer discount percent when applicable. |
| **E-Catalog** | Browse/search/filter catalog tab. |
| **Email All Quotes for This Customer** | Shares that customer’s active quotes and archives them. |
| **Email All Saved Quotes** | Shares all active saved quotes; does **not** archive. |
| **Email Current Quote Only** | Shares one quote and moves it to Archive. |
| **Everyday** | Default / Everyday Product Type quote bucket and E-Catalog chip. |
| **Export All Quotes** | Writes CSVs for the customer’s active bucket quotes and archives them. |
| **Export Current Quote Only** | Exports the open quote CSV and archives it. |
| **Export Walk Order CSV** | Walk Order Editor action to export walk-order rows. |
| **Import Order** | Picks CSV/Excel order files and merges into routed quotes. |
| **In Order** | E-Catalog filter for the customer’s walk-order items. |
| **In Stock Only** | E-Catalog filter for in-stock items. |
| **Item # / UPC** | Manual entry field on Scan (quick entry). |
| **List Price** | Catalog list unit; used in email/export List Price column (not confused with sale Price). |
| **Load Quote** | Opens the list of active saved quotes. |
| **MOQ / Minimum Order Quantity** | Smallest order step; first scan adds this many. |
| **NET** | Net-priced item flag; PS takes precedence if both set. |
| **Never Add** | Walk-order flag advising not to add that item for the customer. |
| **New Items** | E-Catalog chip for new-release products. |
| **Previously Ordered Only** | E-Catalog filter for items in prior order/archive history. |
| **Price** | Selling/shelf unit used in order calculations (after PS/NET/discount rules). |
| **Product Type** | Catalog field that drives which quote bucket an item joins. |
| **PS** | Special price flag; overrides NET when both present. |
| **quote_\<id\>.json** | On-phone file holding one quote’s lines and customer snapshot. |
| **quotes_active.json** | Index of active quotes. |
| **quotes_archive.json** | Index of archived/confirmed quotes. |
| **Sale** | E-Catalog chip for sale merchandise. |
| **Scan** | Main scanning tab. |
| **Scan with Camera** | Opens the camera barcode scanner screen. |
| **Seasonal** | E-Catalog chip including seasonal Product Types (incl. Spring/Summer live + legacy Summer). |
| **Setup** | Admin/data tab (**LOAD PRODUCTS**, **LOAD CUSTOMERS**, tools). |
| **Share sheet** | Android system UI for emailing/sharing exported files. |
| **showroom_quotes/** | Folder in app documents storing quote indexes and files. |
| **SPRING/SUMMER - GENERAL** | Live Product Type → **Summer General** quote. |
| **SPRING/SUMMER - TOYS** | Live Product Type → **Summer Toys** quote (separate). |
| **Summer General / Summer Toys** | Two separate summer quote buckets (legacy SUMMER * labels map here too). |
| **UPC** | Barcode digits used for scanning and lookup. |
| **Walk order** | Customer-specific sequence of items from walk-order data. |
| **Walk Order Editor** | Setup tool to review/export walk-order CSV. |

---

*End of glossary*
