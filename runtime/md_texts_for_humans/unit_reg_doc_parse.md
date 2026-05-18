# unit_reg_doc_parse
# Document parsing and event registration instruction
# Applicable to: all unit schemas (findo, bteam, modelprod)
# Policy reference: for findo unit — gd_018_policies WHERE policy_id = 'findo_internal'

**INSTRUCTION START**

---

# Principles (MANDATORY)

---

## Basic guidance

* Operation = canonical class
* Catchstring = mapping pattern
* 1 operation → many catchstrings
* ALWAYS prefer REUSE over CREATION

---
## Transaction Integrity

All processing per document must be executed within a single transaction:

```sql
BEGIN;
-- all inserts here
COMMIT;
-- on error: ROLLBACK
```

---
## System Boundary

AI Agent MUST NOT engage any DB elements besides those included in following list:

```
<UNIT_SCHEMA>.e_001_events_registry
<UNIT_SCHEMA>.e_002_entries
<UNIT_SCHEMA>.d_011_economic_operations
<UNIT_SCHEMA>.d_012_operation_catchstrings
glob.gd_003_entities
glob.gd_002_currencies
glob.gd_015_documents
```

---
## Determinism Requirement

```
same input → same:
- entity_id
- operation_id
- currency_code
```

---

# Steps

---

## 1 Data grabbing

---
### Step 1.1
- Parse `C:\Users\Lenovo\Documents\Clarissa_folder\Unit_Folders\<UNIT_SCHEMA>\<UNIT_SCHEMA>_primary_documents` folder
- Identify all present subfolders
- Check presence of `\processed` subfolder. IF absent — report in chat channel

---
### Step 1.2
- Enter every subfolder as identified in Step 1.1 EXCEPT FOR `\processed` subfolder
- Identify all existing data files which represent documents
- For each file identified, check using `file_exists_in_processed` whether it has already been processed
- EXCLUDE any files already present in processed folder from further processing
- Report count of skipped files in final summary

---

## 2 Document Registration

---
### Step 2.1
For every data file identified in Step 1.2 AI Agent needs to formulate/identify and extract following data items:

* `document_type` → based on system filetype
    ILLUSTRATION: `file.pdf` → `PDF Document`, `file.csv` → `CSV File`
* `document_date` → date of document formulation as stated on the face of file
    ILLUSTRATION: "invoice #RT58938 dated September 12, 2026" → `document_date = 2026-09-12`
* `face_id` → document identification number as stated on the face of document
    ILLUSTRATION: "invoice #RT58938" → `face_id = RT58938`
* `file_name` → file system name of the file in question

RULE
* Fail condition: in cases where files cannot be accessed, file is subject to processing in accordance with Step 2.3

---
### Step 2.2
Perform:

```sql
INSERT INTO glob.gd_015_documents
    (document_type, document_date, face_id, file_name)
VALUES (%s, %s, %s, %s)
RETURNING document_id;
```

---
### Step 2.3 — Ambiguity and error reporting

RULE
* In case AI Agent cannot perform requirements of Section 2 of this INSTRUCTION it must:
    - exclude document from processing in subsequent Sections
    - add document to the error array indicating Step 2 as failure point and reason

---

## 3 Entity registration

---
### Step 3.1 — Extract from each document:
* `legal_name` (exact, with UAB/LTD/etc.)
* `entity_reg_number` (if present)
* `vat_id` (if present)
* `tax_id` (if present)
* `country_code`
* `legal_address` — AI Agent Decision: what constitutes legal address for this counterparty based on document content

---
### Step 3.2 — Match (STRICT ORDER):

```sql
-- 1st: match by entity_reg_number
SELECT entity_id FROM glob.gd_003_entities WHERE entity_reg_number = %s;

-- 2nd: match by tax_id
SELECT entity_id FROM glob.gd_003_entities WHERE tax_id = %s;

-- 3rd: match by vat_id
SELECT entity_id FROM glob.gd_003_entities WHERE vat_id = %s;

-- 4th: match by normalized_name (fallback)
SELECT entity_id FROM glob.gd_003_entities WHERE normalized_name = %s;
```

---
### Step 3.3 — Normalize name for matching:
* uppercase
* remove punctuation
* optionally remove legal suffixes for matching ONLY

ILLUSTRATION: `"UAB Findo Finansai"` → `"FINDO FINANSAI"`

---
### Step 3.4 — AI Agent Decision:
```
IF match found → reuse entity_id
ELSE → create new entity
```

---
### Step 3.5 — Create entity IF REQUIRED:

```sql
INSERT INTO glob.gd_003_entities
    (entity_reg_number, legal_name, normalized_name, tax_id, vat_id, country_code, legal_address)
VALUES (%s, %s, %s, %s, %s, %s, %s)
RETURNING entity_id;
```

RULES
* `legal_name` MUST preserve exact document wording
* `normalized_name` used ONLY for matching
* NEVER create duplicates with minor variations
* `entity_reg_number` is the strongest identifier
* `legal_address` may be NULL if not present on document

---
### Step 3.6 — Ambiguity and error reporting

RULE
* In case AI Agent cannot perform requirements of Section 3 it must:
    - exclude document from processing in subsequent Sections
    - add document to the error array indicating Step 3 as failure point and reason

---

## 4 Currency recording

---
### Step 4.1
From each document identified in Step 1.2 extract all currencies mentioned.

---
### Step 4.2 — Normalize to ISO 4217:

ILLUSTRATION
```
€ → EUR
$ → USD
₴ → UAH
```

---
### Step 4.3 — Match:

```sql
SELECT currency_code FROM glob.gd_002_currencies
WHERE currency_code = %s;
```

---
### Step 4.4 — AI Agent Decision:
```
IF exists → reuse
ELSE → create ONLY if valid ISO 4217 code
```

RULE
* AI Agent MUST NOT invent currency codes

---
### Step 4.5 — Ambiguity and error reporting

RULE
* In case AI Agent cannot perform requirements of Section 4 it must:
    - exclude document from processing in subsequent Sections
    - add document to the error array indicating Step 4 as failure point and reason

---

## 5 Event Processing

---

### Step 5.1 — Event Extraction and Classification

For each document identified in Step 1.2 and processed in Section 2, AI Agent must process events one at a time. For each individual event:

---
**5.1.1 — Extract event fields:**

* `event_date` — date of the economic event as it occurred in reality
* `entity_1_id` (from Section 3)
* `entity_2_id` (from Section 3)
* `amount` — gross amount as stated on document face, positive numeric
* `currency_code` (from Section 4) — original document currency
* `raw_description` — verbatim description from document
* `document_id` (from Section 2)
* `origin_object_type` = `LOGICAL_DOCUMENT_OBJECT` (evidence file exists in data storage)
* `origin_object_id` = `document_id` for LOGICAL_DOCUMENT_OBJECT; NULL for RULE_APPLICATION_INSTANCE

Each event must be:
* minimal
* bilateral (two entities)
* indivisible
* free of accounting semantics

---
**5.1.2 — Determine economic nature:**

AI Agent must determine the ABSTRACT ECONOMIC NATURE of the event — not the specific vendor or document reference.

RULE
* `operation_name` must describe WHAT TYPE of economic event occurred, not WHO was involved or WHICH specific service was provided
* `operation_code` must be reusable across all vendors providing similar services
* Think at the level of: "what would an accountant call this type of transaction?"

CORRECT level of abstraction:
* Cloud infrastructure cost → `CLOUD_SERVICE_COST`
* Google Ads invoice → `ADVERTISING_COST`
* Legal services invoice → `PROFESSIONAL_SERVICES`
* Bank wire fee → `BANK_CHARGE`
* Domain renewal → `HOSTING_COST`
* Software subscription → `SOFTWARE_SUBSCRIPTION_COST`

INCORRECT level of abstraction (too specific — these belong in catchstrings, not operations):
* `CLOUDFLARE_SERVICE_CHARGE` ❌ — vendor-specific
* `GOOGLE_ADS_DECEMBER` ❌ — includes period reference
* `INVOICE_RT58938` ❌ — document reference

ILLUSTRATION
```
Invoice from: Cloudflare Inc, Description: Pro Plan + Rate Limiting
→ operation_name: Cloud Service Cost
→ operation_code: CLOUD_SERVICE_COST
→ catchstring:    CLOUDFLARE PRO PLAN
```

---
**5.1.3 — Derive catchstring:**

RULES
* make all words uppercase
* remove numbers and document references
* remove noise words (of, the, for, etc.)
* preserve semantic meaning
* catchstring identifies the SPECIFIC vendor/service pattern, not the abstract operation

ILLUSTRATION
```
AMZN EU PAYMENT 123       → AMAZON PAYMENT
Google advertising cost   → GOOGLE ADS COST
Cloudflare Pro Plan sub   → CLOUDFLARE PRO PLAN
```

---
**5.1.4 — Resolve operation_id:**

```sql
SELECT operation_id FROM <UNIT_SCHEMA>.d_012_operation_catchstrings
WHERE catchstring = %s;
```

IF match found → reuse `operation_id`

ELSE → create new operation:

```sql
INSERT INTO <UNIT_SCHEMA>.d_011_economic_operations
    (operation_code, operation_name)
VALUES (%s, %s)
RETURNING operation_id;
```

RULES
* `operation_code` must be uppercase, underscore-separated
* `operation_code` must be reusable across all schemas

Then register catchstring:

```sql
INSERT INTO <UNIT_SCHEMA>.d_012_operation_catchstrings
    (operation_id, catchstring)
VALUES (%s, %s);
```

---
**5.1.5 — Record event:**

Now that all fields including `operation_id` are known, perform:

```sql
INSERT INTO <UNIT_SCHEMA>.e_001_events_registry
    (event_date, entity_1_id, entity_2_id, amount, currency_code,
    raw_description, operation_id, origin_object_type, origin_object_id, document_id)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
RETURNING event_id;
```

---
**5.1.6 — Execute recognition date and amount estimation:**

RULE
* Immediately after recording each event in Step 5.1.5, AI Agent MUST execute
  subinstruction `findo_recon_date_amount_estimate` for findo unit
* This subinstruction determines recognition date(s) and proportional amounts
  and populates `<UNIT_SCHEMA>.e_002_entries`
* This step is MANDATORY — no event may be left without a corresponding entry in e_002_entries
* Policy basis: `gd_018_policies` WHERE `policy_id = 'findo_internal'`

NOTE: For bteam and modelprod units — equivalent subinstructions will be referenced
here once developed. Until then, skip Step 5.1.6 for those units.

---

Repeat Steps 5.1.1 through 5.1.6 for each event in the document.

---

### Step 5.2 — Ambiguity and error reporting

RULE
* In case AI Agent cannot perform requirements of Section 5 for any event it must:
    - exclude that event from processing
    - add document ID and event description to the error array indicating the step and reason of failure

---

## 6 Summary and File Management

---
### Step 6.1 — Compile processing results

Upon completion of all previous steps, AI Agent must compile a summary report containing:

**Processed successfully:**
* Total number of documents processed
* Total number of events registered
* Total number of entries created in e_002_entries
* Total number of new entities created
* Total number of new operations created
* Total number of new catchstrings registered
* Total number of files skipped (already in processed folder)

**Failed documents:**

| Document | File Name | Failed at Step | Reason |
|----------|-----------|----------------|--------|
| face_id  | file_name | Step X.X       | reason |

---
### Step 6.2 — Move successfully processed files

For every document that was successfully processed (all steps 2-5 completed without error):

Move the file to the processed subfolder using the `move_file` tool:
* `unit` = current `<UNIT_SCHEMA>`
* `filename` = file_name of the document
* `from_subfolder` = the year/month subfolder where the file was found (e.g. `2021 08`)
* `to_subfolder` = `processed`

RULE
* Only move files that completed ALL steps 2-5 successfully
* Files with ANY failure in steps 2-5 must remain in their original location
* If `move_file` fails — report in summary but do not mark document as failed

---

## 7 Output

---
### Step 7.1 — Telegram report

AI Agent must post the summary report in Telegram chat.

If failed documents list is not empty — flag with ⚠️ and list each failed document with its reason.

Failed documents remain in their original folder for AI review.

RULE
* This step must execute regardless of whether any documents failed

**END OF INSTRUCTION**
