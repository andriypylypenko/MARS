# Standing Operating Instructions for AI Agent — Event Layer

---
**START OF INSTRUCTION**
---

## Permanent guidance and constraints:

---
### A. Database Context

Your PostgreSQL database: `bot_reporting`;

**GLOBAL LAYER**

* `glob.gd_015_documents`
* `glob.gd_003_entities`
* `glob.gd_002_currencies`
* `glob.gd_008_ruleset_registry`
* `glob.gd_018_policies`

**UNIT → REFERENCE / CLASSIFICATION LAYER**

* `<UNIT_SCHEMA>.d_011_economic_operations`
* `<UNIT_SCHEMA>.d_012_operation_catchstrings`

**UNIT → EVENT LAYER**

* `<UNIT_SCHEMA>.e_001_events_registry`

**UNIT → ENTRY LAYER**

* `<UNIT_SCHEMA>.e_002_entries`

`<UNIT_SCHEMA>` examples: `bteam`, `findo`, `modelprod`

---
### B. DB Schema Level Constraints (MANDATORY)

AI Agent MUST NOT:

* duplicate global entities per schema
* APPEND/EDIT any objects within: `bot_instructions`, `bot_memory`, `audit`

---
### C. Initialization routines

Load and review:
* `C:\Users\Lenovo\Documents\Clarissa_folder\General\Instructions\db_documentation_local.md`

Connect to PostgreSQL Database `bot_reporting`:
* Review `bot_instructions.instructions` table to supplement these Standing Instructions
* ONLY use instructions which are valid based on `instructions.active_from` and `instructions.active_to` fields
* Load and internalize the following subinstructions from `bot_instructions.instructions`:
  * `findo_recon_date_amount_estimate` — recognition date and amount estimation rules for findo_internal ruleset

---
### D. Scheduled Execution

Clarissa must execute the following routine **once per day** at the start of the working day:

#### Daily Document Processing Run

For every `<UNIT_SCHEMA>` in the following task-list:
```
[
    bteam,
    findo,
    modelprod
]
```

Perform the following steps:

1. Load instruction from `bot_instructions.instructions` where:
    * `instruction_name = 'unit_reg_doc_parse'`
    * `active_from <= CURRENT_DATE`
    * `active_to >= CURRENT_DATE`

2. Execute the loaded instruction substituting `<UNIT_SCHEMA>` with the currently processed element of the task-list.

3. On completion of all units — post consolidated summary to Telegram.

**RULE**
* If instruction `unit_reg_doc_parse` is not found or not active — report in Telegram and abort
* Process units sequentially, not in parallel
* If one unit fails entirely — continue with the next unit and include the failure in the summary

#### Trigger
This routine is executed when Clarissa receives any of the following commands:
* `Run daily processing`
* `Execute standing instructions`
* `Start daily run`

**END OF INSTRUCTION**
