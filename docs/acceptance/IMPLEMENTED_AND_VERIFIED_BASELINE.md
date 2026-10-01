# Implemented and Verified Baseline

Reconstructed 2026-09-30. PASS is preserved only where supplied acceptance evidence says PASS; code presence is not acceptance. [Source register](../project/PROJECT_MASTER_RECORD.md#authority-and-source-register). M = [public baseline migration](../../supabase/migrations/20260922071000_production_baseline_20260922.sql). Repo references below are VERIFIED AGAINST REPO; historical test outcomes remain RECORD-SOURCED and were not rerun.

| Capability | Status | Evidence / Step | Repo reference if verified | Qualification |
|---|---|---|---|---|
| Meal Delivery structured intake | IMPLEMENTED / VERIFIED | S3 Step 30: real WhatsApp → DB, PROCESSED, LEAD_CREATED=1, AI_UPDATED=1 | M:45 finalize; service_details storage | Workflow/extraction and live outcome RECORD-SOURCED; test lead cleaned up |
| Home Care extraction | IMPLEMENTED / VERIFIED | S3 Step 31: weekdays, afternoon, two-hour duration and care needs | M:1123 lead schema | Extraction/normalization implementation absent from repo |
| Home Cleaning extraction | IMPLEMENTED / VERIFIED | S3 Step 32: district, size, schedule, needs; deterministic time-period correction | M:1123 | Live extraction proof RECORD-SOURCED |
| Physiotherapy extraction | IMPLEMENTED / VERIFIED | S3 Step 33: explicit rehabilitation/function descriptions | M:1123 | No medical suitability acceptance implied |
| Medical Escort extraction | IMPLEMENTED / VERIFIED | S3 Step 34: appointment exclusivity, requirement and relative-date normalization | M:1403 context includes distinct appointments | Deterministic workflow resolver RECORD-SOURCED; no universal parser acceptance |
| Multi-service routing/isolation | IMPLEMENTED / VERIFIED | S3 Step 35 controlled smoke PASS: separate services, reuse, ambiguity rejection, category guard | M:809, 1720, 2534, 2538 | Code checked; smoke not rerun |
| Canonical unknown correction | IMPLEMENTED / VERIFIED | S3 Steps 35/37: NOT NULL failure corrected; indexes/retry integrity verified | M:809, 1167, 2538 | Stored unknown is not NULL; internal RPC parameter may be normalized through NULL |
| Active Lead Context and multi-turn continuation | IMPLEMENTED / VERIFIED | S3 Step 36: same lead continued; second service isolated; AI_UPDATED=2 | M:1403 `b2c_list_active_lead_contexts` | Workflow input change/live tests RECORD-SOURCED |
| Failure and retry lifecycle | IMPLEMENTED / VERIFIED | S3 Step 37: FAILED attempt1 → PROCESSING attempt2 → PROCESSED; cleared error | M:1484, 1602, 45 | Atomic RPC definitions checked; workflow error wiring not stored |
| Safe error summaries | IMPLEMENTED / VERIFIED | S3 Step 37: controlled safe error test; rotation/redaction recorded | M:1484 stores p_error | Handler sanitization RECORD-SOURCED; RPC is not a sanitizer |
| Webhook authenticity gate | IMPLEMENTED / VERIFIED | S3 Step 38: valid match; invalid branch true=0/false=1 and DB rows=0 | None: n8n export absent | RECORD-SOURCED; test data cleaned up; today's credential/config not checked |
| Public baseline capture and migration artifact | PASS / VERIFIED | S4 Step 39: exact snapshot/migration match | Baseline + M; commits c019ddb/f491fd3 | Hash, size, line count and Git history independently checked |
| Clean-room rebuild and migration adoption | PASS / VERIFIED | S4 Step 39: fresh/local rebuild, ledger, remote repair-applied, post-adoption integrity | Migration version 20260922071000 | PASS RECORD-SOURCED; remote adoption did not rerun baseline SQL on production |
| Human-owned lead guard | PASS / VERIFIED | S4 Step 39 guard/marker verification | M:1720, 1819, 1832 | Definitions independently checked; acceptance not rerun |
| Smart Button interaction design | APPROVED DESIGN ONLY | S4 Step 40A operational approval | None: review PDF absent | APPROVED / COMPLETE is design acceptance, not implementation |
| WOZTELL Smart Button payload/update path | NOT YET VERIFIED | S4 §§9–10 | None | Encoding, deterministic update and multi-turn/live acceptance not established |
| Full natural-time parser / wound-care conditional implementation | NOT YET VERIFIED | S4 §9 | None | Approved product behaviour, not demonstrated implementation |
| Holiday data and outbound calendar integration | DEFERRED | S3 §7; S4 Step 40G | M:1582 availability function, 2447 blackout table | Function presence does not prove calendar rows or outbound integration |
| B10 / R1-01G / G4.6L | PASS / FROZEN | S5 final handover; S6 corroborates | None: private package absent | Historical acceptance RECORD-SOURCED; workstream CLOSED |
| B10-PGRST exposure closure | PASS / CLOSED | S5 Dashboard + override inventory PASS / CLOSED | None | Hosted configuration not independently rechecked |
| Real bootstrap, signing credential, gateway activation | DEFERRED | S5 §§9–10 | None | B10 does not authorize them; independent bootstrap gate |
| Knowledge Base, reply policy, outbound/live acceptance and follow-up engine | DEFERRED | S4 Step 40B–H and later workstreams | None | No acceptance inferred from historical proposal or SQL references |

## Step 39 independently verified artifact evidence

Both [snapshot](../../supabase/baseline/production_public_schema_20260922.sql) and M are 81,436 bytes / 2,791 lines and SHA-256:

```text
08E8E0D9DDCCF1AB5444A51FFCDFADA2AD996C4E2A6AA07C630D50766E7AF37F
```

Commits: `25e4ca896b434f626847e6b2bb3fcc69076f4a9f`, `c019ddb2a3156cbc67c202308bfb9884a13059f6`, `f491fd3d946114861bb6ad3ef835bccc8813503c`. S4 reports migration history `20260922071000 | 20260922071000`, production ledger count 1/latest version 20260922071000, pre/post-adoption integrity PASS. Those remote/rebuild outputs are not stored here.

## B10 acceptance lineage — RECORD-SOURCED

S5 is the single primary authority. B14 contract PASS/FROZEN → B15-R1 BLOCK (five remediation areas) → R2 PASS → first execution failed pre-COMMIT on identity assertion, full rollback independently confirmed (`b2c_private` absent, function count 0, no commit uncertainty) → R3 narrow identity fix (`to_regprocedure` plus exact same-name count) PASS → MIGRATION_EXECUTION_PASS / COMMIT_RETURNED_SUCCESSFULLY.

Verification corrections: R4 PUBLIC pseudo-role inspection; R5 NULL/empty ACL arrays; R6 trigger catalog field; R7 ORDER BY alias expression. They were read-only implementation corrections, not DB mutations. Earlier packs are superseded by final R7.

Final R7 completed V01–V19 per S5. Recorded evidence covers ownership, schema/table/column ACL, nine function identities/security/search_path/EXECUTE ACL, triggers/deferred posture, constraints, non-unique candidate index, no private views/wrappers, reviewed definitions/dependencies, no private dynamic SQL/SET ROLE/generic dispatch, global SECURITY DEFINER review with no new blocker and V18 empty state. The supplied record does not separately enumerate V17's result; no missing detail is invented. V19 was resolved by B14-5C Model B, with ROW_COUNT=0 informational. Dashboard and applicable override inventory subsequently closed B10-PGRST; final B10 PASS/FROZEN follows those gates.

Authoritative recorded R3 migration SHA-256:

```text
98eba677642ecb3405b0199c7fa7cee0ac694fc94a94c43ec75030c8ec82eb4a
```

Package filenames/remaining hashes and frozen obligations are maintained in the [security baseline](../architecture/B10_BACKEND_SECURITY_BASELINE.md). No original package/output was independently hashed here.

## Explicit limitations and stopped claims

No new runtime/live acceptance was performed. Product approval is in the [product spec](../product/SALES_ENQUIRY_PRODUCT_SPEC.md). Legacy SQL categories remain broader than its approved customer-facing set; therefore the claim of fully synchronized Step 40A implementation is stopped. Missing B10 assets prevent a complete repo-only rebuild/security comparison; they do not downgrade historical B10 acceptance or authorize new infrastructure.
