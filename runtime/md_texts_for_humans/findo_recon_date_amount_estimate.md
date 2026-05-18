# findo_recon_date_amount_estimate
# Subinstruction: Recognition Date and Amount Estimation
# Applicable to: findo unit, findo_internal ruleset
# Policy reference: glob.gd_018_policies WHERE policy_id = 'findo_internal'

**INSTRUCTION START**

---

# PURPOSE

This instruction governs how AI Agent determines, for each event recorded in
`findo.e_001_events_registry` under the `findo_internal` ruleset:

1. Recognition date(s) — when the economic effect is recognized in reporting
2. Whether an event must be split into multiple entries (multi-period)
3. Proportional amount per entry where split applies
4. Confidence status of each determination

Results are stored in `findo.e_002_entries`.

This instruction is invoked from `unit_reg_doc_parse` Step 5.1.6 immediately
after each event is recorded.

---

# POLICY BASIS

All decisions in this instruction are grounded in `findo_internal` policy
stored in `glob.gd_018_policies`. Key elements referenced:

| element_id | Topic |
|------------|-------|
| findo_internal_1_3 | Reporting currency: USD |
| findo_internal_1_4 | FX rate source: FRED + national banks |
| findo_internal_1_5 | Rate code: rate_comp |
| findo_internal_2_1 | Revenue recognition — general |
| findo_internal_2_2 | Revenue — point in time |
| findo_internal_2_3 | Revenue — over time |
| findo_internal_2_4 | Revenue — practical expedient |
| findo_internal_2_5 | Expense accrual — general |
| findo_internal_2_6 | Expense accrual — timing |
| findo_internal_2_7 | Expense — invoice date default (failsafe) |
| findo_internal_2_8 | Provisions |
| findo_internal_2_9 | Employee costs — general |
| findo_internal_2_10 | Wages and salaries |
| findo_internal_2_11 | Bonuses |
| findo_internal_2_12 | Paid leave |
| findo_internal_2_13 | Lease expenses |
| findo_internal_2_14 | Interest expense |
| findo_internal_2_15 | Prepayments |
| findo_internal_2_16 | Period split rule |
| findo_internal_2_17 | FX translation (handled by ledger view, not this instruction) |

---

# MANDATORY PRINCIPLES

* Every event MUST produce at least one entry in `findo.e_002_entries`
* `recon_date_automatic` MUST always be populated — it is NEVER NULL
* Default failsafe: IF no other rule applies → `recon_date_automatic = document_date`
* AI Agent MUST record the `element_id` of the policy rule applied in `recon_note`
* AI Agent MUST NOT determine recognition dates without policy basis
* Amount in entries is always in ORIGINAL document currency — FX conversion to USD
  is performed by the ledger view using `rate_comp` rates per `findo_internal_2_17`

---

# STEP-BY-STEP FRAMEWORK

---

## STEP 1 — Identify event type

From the event data and source document determine:

```
A. Revenue event     — entity receives payment or issues invoice for goods/services
B. Expense event     — entity makes payment or receives invoice for goods/services
C. Employee cost     — wages, salary, bonus, compensated leave
D. Lease payment     — rent, short-term lease, low-value asset lease
E. Interest          — loan interest accrual
F. Prepayment        — payment made before service/goods delivery
G. Other             — does not fit above categories
```

RULE
* Determination is based on: `raw_description`, `operation_code`, counterparty nature
* If unclear → classify as G and apply failsafe default

---

## STEP 2 — Check for service period on document face

Examine the source document for explicit service period statement.

INDICATORS of service period:
* `"for services rendered between [date] and [date]"`
* `"subscription period: [date] — [date]"`
* `"lease for [month] [year]"`
* `"salary for [month] [year]"`
* Any date range explicitly stated as basis for the charge

```
IF service period found → proceed to STEP 3
IF no service period found → proceed to STEP 7 (failsafe)
```

---

## STEP 3 — Determine period boundaries

From the service period identified in STEP 2:

```
period_start = first day of service as stated on document
period_end   = last day of service as stated on document
total_days   = period_end - period_start + 1
```

ILLUSTRATION
```
"Services rendered March 5 – April 15, 2026"
period_start = 2026-03-05
period_end   = 2026-04-15
total_days   = 41
```

---

## STEP 4 — Check for month boundary crossing

```
IF period_start and period_end fall within SAME calendar month:
    → Single entry, no split required
    → proceed to STEP 6 (single entry determination)

IF period spans MORE THAN ONE calendar month:
    → Split required per findo_internal_2_16
    → proceed to STEP 5 (period split)
```

---

## STEP 5 — Period split (multi-month events)

Policy reference: `findo_internal_2_16`

For each calendar month within the service period:

```
month_start  = MAX(period_start, first day of month)
month_end    = MIN(period_end, last day of month)
month_days   = month_end - month_start + 1
entry_amount = total_event_amount * (month_days / total_days)
recon_date   = last calendar day of the month
entry_id     = '<event_id>-findo_internal-<sequence>'
```

ILLUSTRATION
```
Event: amount = 900.00, currency = EUR, service March 5 – April 15 (41 days)
Note: 900.00 EUR is the original document amount — USD conversion in ledger view

Entry 1:
    month_start  = 2026-03-05
    month_end    = 2026-03-31
    month_days   = 27
    entry_amount = 900.00 * (27/41) = 592.68
    recon_date   = 2026-03-31
    entry_id     = '42-findo_internal-1'
    policy_ref   = findo_internal_2_16

Entry 2:
    month_start  = 2026-04-01
    month_end    = 2026-04-15
    month_days   = 14
    entry_amount = 900.00 * (14/41) = 307.32
    recon_date   = 2026-04-30
    entry_id     = '42-findo_internal-2'
    policy_ref   = findo_internal_2_16
```

RULES
* Sum of all entry_amounts MUST equal total_event_amount (apply rounding to last entry)
* `recon_date` is always the LAST DAY of the calendar month
* `entry_id` sequence starts at 1 per event per ruleset

---

## STEP 6 — Single entry recognition date determination

Determine recognition date based on event type from STEP 1:

### A. Revenue event
Policy reference: `findo_internal_2_1`, `findo_internal_2_2`, `findo_internal_2_3`, `findo_internal_2_4`

```
IF performance obligation satisfied at point in time:
    recon_date = date of control transfer (invoice date or confirmed delivery date)
    policy_ref = findo_internal_2_2

IF performance obligation satisfied over time AND within single month:
    recon_date = last calendar day of service month
    policy_ref = findo_internal_2_3

IF practical expedient applies (invoice amount = value delivered to date):
    recon_date = invoice date
    policy_ref = findo_internal_2_4
```

### B. Expense event
Policy reference: `findo_internal_2_5`, `findo_internal_2_6`, `findo_internal_2_7`

```
IF service period stated AND falls within single month:
    recon_date = last calendar day of service month
    policy_ref = findo_internal_2_6

IF no service period stated on document face:
    recon_date = document_date (invoice date)
    policy_ref = findo_internal_2_7
```

### C. Employee cost
Policy reference: `findo_internal_2_9`, `findo_internal_2_10`, `findo_internal_2_11`, `findo_internal_2_12`

```
IF wages / salary:
    recon_date = last calendar day of month service rendered
    policy_ref = findo_internal_2_10

IF bonus:
    recon_date = last day of performance period
    policy_ref = findo_internal_2_11

IF paid leave / compensated absence:
    recon_date = last calendar day of month absence occurs
    policy_ref = findo_internal_2_12
```

### D. Lease payment
Policy reference: `findo_internal_2_13`

```
recon_date = last calendar day of lease month
policy_ref = findo_internal_2_13
```

### E. Interest expense
Policy reference: `findo_internal_2_14`

```
recon_date = last calendar day of accrual period per loan agreement
policy_ref = findo_internal_2_14
```

### F. Prepayment
Policy reference: `findo_internal_2_15`

```
IF delivery/service date known:
    recon_date = date of service delivery or goods receipt
    policy_ref = findo_internal_2_15

IF delivery date unknown at time of processing:
    recon_date = document_date (temporary failsafe)
    status     = 'pending'
    recon_note = 'Prepayment — delivery date unknown, requires AI review | findo_internal_2_15'
```

### G. Other
Policy reference: `findo_internal_2_7`

```
recon_date = document_date (failsafe)
status     = 'pending'
recon_note = 'Event type undetermined — failsafe applied | findo_internal_2_7'
```

---

## STEP 7 — Failsafe default

Applied when:
* No service period found in STEP 2, OR
* Event type is G (Other), OR
* AI Agent cannot determine recognition date with confidence

```
recon_date_automatic = document_date
status               = 'pending'
recon_note           = 'Failsafe default applied — AI review required | findo_internal_2_7'
```

---

## STEP 8 — Record in findo.e_002_entries

For each entry determined in STEPS 5, 6, or 7:

```sql
INSERT INTO findo.e_002_entries
    (entry_id, event_id, ruleset_id, recon_date_automatic,
     recon_date_reviewed, amount, currency_code, status, recon_note)
VALUES
    (%s, %s, 'findo_internal', %s, NULL, %s, %s, 'pending', %s);
```

RULES
* `recon_date_reviewed` is always NULL at initial insert
* `status` = 'pending' at insert — updated in STEP 9
* `recon_note` MUST reference at least one `element_id` from `gd_018_policies`
* `entry_id` format: `'<event_id>-findo_internal-<sequence>'` starting at 1
* `currency_code` = original document currency (NOT reporting currency USD)

---

## STEP 9 — Status determination

After inserting all entries for this event, update `status` per entry:

```
IF recon_date_automatic determined by clear policy rule
   AND no ambiguity encountered
   AND event type NOT G (Other)
   AND event type NOT F with unknown delivery date:
    → status = 'accepted'

IF recon_date_automatic = document_date due to failsafe:
    → status = 'pending'

IF event type = F AND delivery date unknown:
    → status = 'pending'

IF any uncertainty in determining recon_date:
    → status = 'pending'
    → recon_note must describe the uncertainty
```

```sql
UPDATE findo.e_002_entries
SET status = %s
WHERE entry_id = %s AND ruleset_id = 'findo_internal';
```

RULE
* `'overridden'` status is NEVER set by this instruction
* `'overridden'` is reserved for cases where `recon_date_reviewed` differs from `recon_date_automatic`

---

## STEP 10 — Validation

Before committing transaction:

```
CHECK: SUM of all entry amounts for this event = event.amount
CHECK: All entries have recon_date_automatic populated (NOT NULL)
CHECK: All entries have entry_id populated
CHECK: All entries have recon_note referencing at least one policy element_id
CHECK: All entries have status set ('accepted' or 'pending' — never NULL)

IF any check fails → ROLLBACK and add event_id to error array with reason
```

---

## STEP 11 — Ambiguity and error reporting

RULE
* In case AI Agent cannot perform requirements of this instruction:
    - Set `recon_date_automatic` = `document_date` (failsafe)
    - Set `status` = `'pending'`
    - Set `recon_note` = reason for failure + `' | REQUIRES AI REVIEW | findo_internal_2_7'`
    - DO NOT exclude event from `e_002_entries`
    - Add `event_id` to error array with reason

NOTE: Unlike `unit_reg_doc_parse` error handling, this instruction NEVER excludes
an event entirely — every event must have at least one entry with a failsafe date.

**END OF INSTRUCTION**
