# Database Documentation — bot_reporting

---

## Database Overview

Database: `bot_reporting`
PostgreSQL 18, UTF-8 encoding

---

## Schema Map

| Schema | Purpose |
|--------|---------|
| `glob` | Global dimensions — shared reference data across all units |
| `findo` | Financial operations domain — classification layer |
| `bteam` | Operational unit — bteam events |
| `modelprod` | Modelling and production domain |
| `audit` | Immutable audit trail of all write operations |
| `bot_memory` | Clarissa's conversation memory |
| `diagnostic` | Test and diagnostic tables |
| `public` | Legacy/test tables |

---

## Naming Conventions

| Prefix | Meaning |
|--------|---------|
| `d_xxx` | Reference table — constant classification data |
| `r_xxx` | Rule table — parameters with active_period mechanism |
| `e_xxx` | Event table — real-world economic events |
| `w_xxx` | Processed/ledger data |
| `s_xxx` | Service tables |
| `g` prefix | Global schema element (e.g. `gd_xxx`) |
| `a` prefix | Audit schema element (e.g. `aw_xxx`) |

---

## Global Schema (`glob`)

### `glob.gd_001_calendar`
Working day calendar.

### `glob.gd_002_currencies`
Currency definitions.
Columns: `currency_code` (char PK), `currency_name`, `minor_units`

### `glob.gd_003_entities`
Master registry of legal entities.
Columns: `entity_id` (bigint PK), `entity_code`, `country_code`, `legal_name`,
`normalized_name`, `tax_id`, `vat_id`, `legal_address`

Entity matching priority: VAT ID → TAX ID → normalized_name

### `glob.gd_004_exchange_rates`
Historical foreign exchange rates.
Columns: `rate_id` (bigint PK), `rate_date`, `base_currency`, `quote_currency`,
`rate_value`, `rate_code`

### `glob.gd_005_inflation_rates`
Annual inflation reference data.

### `glob.gd_006_movable_holidays`
Country-specific movable holidays registry.

### `glob.gd_007_people`
Master registry of physical persons.

### `glob.gd_008_ruleset_registry`
Registry of rule sets used by system calculations.
Columns: `ruleset_id` (text PK), `ruleset_name`, `description`, `active_from`, `active_to`,
`reporting_currency`, `rate_source`

### `glob.gd_010_units`
Registry of operational units.
Columns: `unit_id` (bigint PK), `unit_code`, `unit_name`

### `glob.gd_011_holidays`
Holiday calendar.

### `glob.gd_012_entity_calendar_overrides`
Entity-specific calendar overrides.

### `glob.gd_013_country_calendar`
Country calendar definitions.

### `glob.gd_014_rate_codes`
Foreign exchange rate code definitions.

### `glob.gd_015_documents`
Document registry — all processed source documents.
Columns: `document_id` (bigint PK), `document_type`, `document_date`,
`face_id`, `file_name`, `registered_at`

---

## Financial Operations Schema (`findo`)

### `findo.d_011_economic_operations`
Operation type dictionary — canonical classification of economic events.
Columns: `operation_id` (bigint PK), `operation_code`, `operation_name`

Rules:
- `operation_code` must be stable, uppercase, underscore-separated
- Reusable across all unit schemas
- ALWAYS prefer reuse over creation

### `findo.d_012_operation_catchstrings`
Text pattern to operation type mapping.
Columns: `catchstring_id` (bigint PK), `operation_id` (FK), `catchstring`

Rules:
- 1 operation → many catchstrings
- catchstring = normalized text pattern (uppercase, no numbers)

### `findo.e_001_events_registry`
Financial events for the findo unit.
Columns: `event_id` (bigint PK), `event_date`, `entity_1_id`, `entity_2_id`,
`amount`, `currency_code`, `raw_description`, `operation_id`,
`origin_object_type`, `origin_object_id`, `document_id`

### `findo.e_002_entries`
Entry table — stores recognition dates, amounts, and review status per event per ruleset.

Columns:

| Column | Type | Description |
|--------|------|-------------|
| `entry_id` | VARCHAR | PK (composite with ruleset_id) — unique entry identifier |
| `event_id` | BIGINT | FK to `e_001_events_registry` (non-unique) |
| `ruleset_id` | TEXT | FK to `glob.gd_008_ruleset_registry` |
| `recon_date_automatic` | DATE | Calculated by ruleset logic |
| `recon_date_reviewed` | DATE | Clarissa's override — NULL means automatic accepted |
| `status` | VARCHAR | `pending` / `accepted` / `overridden` |
| `amount` | NUMERIC | Entry-level amount (may differ from event amount after splitting) |
| `currency_code` | TEXT | Entry-level currency |
| `recon_note` | VARCHAR | Optional note explaining recognition decision |

Primary key: composite `(entry_id, ruleset_id)` — one event can produce multiple entries under multiple rulesets.

Constraints:
- `status` must be one of: `pending`, `accepted`, `overridden`
- Default status: `pending`

Ledger consumption:
```sql
COALESCE(en.recon_date_reviewed, en.recon_date_automatic) AS recon_date
FROM <UNIT_SCHEMA>.e_002_entries en
WHERE en.event_id = e.event_id
  AND en.ruleset_id = <active_ruleset>
```

---

## Unit Schemas (`bteam`, `modelprod`)

Each unit schema contains the same structure:

### `<unit>.d_011_economic_operations`
Unit-specific operation type dictionary (mirrors findo structure).

### `<unit>.d_012_operation_catchstrings`
Unit-specific catchstring mappings.

### `<unit>.e_001_events_registry`
Unit-specific event registry.
Same columns as `findo.e_001_events_registry`.

### `<unit>.e_002_entries`
Unit-specific entry table.
Same structure as `findo.e_002_entries`.

---

## Audit Schema (`audit`)

### `audit.aw_001_audit_log`
Immutable audit trail of all write operations.
Columns: `audit_id` (bigint PK), `table_name`, `row_id`, `operation_type`,
`changed_at`, `changed_by`

Every db_write must be followed by an entry here.

---

## Bot Memory Schema (`bot_memory`)

### `bot_memory.conversations`
Clarissa's persistent conversation memory.
Columns: `id` (bigint PK), `chat_id`, `role`, `content`, `created_at`

Managed automatically — do not write to directly.

---

## Event Layer Principles

* Any complex economic interaction reduces to primitive bilateral events
* Event = minimal, neutral, indivisible
* No accounting semantics in event layer
* `origin_object_type` values:
  - `LOGICAL_DOCUMENT_OBJECT` — event from a document line
  - `RULE_APPLICATION_INSTANCE` — event from rule application
* `event_date` = real-world occurrence date (not recognition date)
* `recon_date` = when the event is recognised under a given ruleset — stored in `e_002_entries`
* Amount = pure numeric, no sign or direction meaning
* Entity pair is unordered — no direction implied

---

## Recognition Date (`recon_date`) Architecture

Recognition date is ruleset-dependent and cannot be stored on the event itself since one event may be recognised differently under different rulesets.

Flow:
```
Event registered in e_001_events_registry
        ↓
Automatic recon_date calculated per ruleset → inserted into e_002_entries (status = pending)
        ↓
Clarissa reviews as part of daily Unit routine
        ↓
Accepts → status = accepted, recon_date_reviewed remains NULL
Overrides → status = overridden, recon_date_reviewed = corrected date
        ↓
Ledger consumes COALESCE(recon_date_reviewed, recon_date_automatic)
```

---

**END OF DOCUMENTATION**