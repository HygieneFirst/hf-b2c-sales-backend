# Sales Enquiry System Baseline

Reconstructed 2026-09-30. Describes captured implementation rather than a new architecture. [Source register](../project/PROJECT_MASTER_RECORD.md#authority-and-source-register). S3 is the historical Steps 30–38 implementation authority; S4 supplies Step 39 and design-only qualifications. PASS evidence belongs in the [acceptance baseline](../acceptance/IMPLEMENTED_AND_VERIFIED_BASELINE.md); private resolver contracts belong in the [B10 baseline](B10_BACKEND_SECURITY_BASELINE.md).

## Evidence boundary and component roles

WOZTELL receives WhatsApp events; n8n orchestrates processing; OpenAI interprets free text and extracts structured facts; Supabase persists leads/messages/events and enforces integrity. These integration roles and wiring are **RECORD-SOURCED** from S3. The repository stores the public SQL snapshot, not an n8n export or deployed configuration.

All SQL references below use [migration M](../../supabase/migrations/20260922071000_production_baseline_20260922.sql), version `20260922071000`. Its definitions are **VERIFIED AGAINST REPO**; today's deployed behaviour was not re-tested.

## Inbound workflow — historically IMPLEMENTED / VERIFIED

S3 §5 names workflow `Osa86r7Ehpo2b1y7` and this sequence (**RECORD-SOURCED**):

```text
WOZTELL Inbound Webhook
→ WOZTELL - Calculate Signature
→ IF - WOZTELL Signature Valid?
→ Filter Sales Hotline TEXT
→ Extract WOZTELL Identifiers
→ Supabase - Reserve Inbound Message
→ IF - Should Process?
→ Get Conversation History
→ Normalize Conversation
→ Supabase - Get Active Lead Contexts
→ Lead Extraction
→ Build Final Output
→ Supabase - Finalize AI Result
```

The webhook preserves raw body (`binary.data`), headers and parsed body. Raw bytes plus Channel Secret produce HMAC-SHA256/Base64; comparison is with `x-woztell-signature`. Invalid signatures terminate before Reserve, AI or database processing. Credential names recorded are `WOZTELL Sales Hotline HMAC` and `HF B2C Supabase Secret`; no values are reproduced. This webhook protocol is separate from the resolver protocol in B10.

## Reserve, finalize and failure lifecycle

**VERIFIED AGAINST REPO**, M lines 45, 1484, 1535, 1602:

- `b2c_reserve_inbound_message`: new message → PROCESSING, attempt 1; FAILED → PROCESSING with incremented attempt count and cleared error; existing PROCESSING/PROCESSED → `should_process = false`.
- `b2c_apply_ai_result_and_mark_processed`: validates extraction, locks the PROCESSING message, routes the lead, creates LEAD_CREATED when appropriate, invokes AI update, marks PROCESSED and clears error in the same database function execution. Reserve and finalize are separate calls, not one transaction spanning AI work.
- `b2c_mark_inbound_message_failed`: changes a PROCESSING message to FAILED and stores the supplied `p_error`; `b2c_mark_inbound_message_processed` is also present.

S3 Step 37 routes error outputs from history, normalization, active-context fetch, extraction, final-output construction and finalize to `Supabase - Mark Message FAILED`. Should Process false is not an error. Safe summaries replace full Axios objects after a historical credential incident, rotation and log redaction. **RECORD-SOURCED**: sanitization is in the workflow handler; the SQL failure RPC stores caller text and does not independently sanitize credentials. Current credential state is not independently verified.

## Lead routing and context

**VERIFIED AGAINST REPO**, M lines 809–1095: `b2c_get_or_create_active_lead_v2` serializes routing by member using an advisory transaction lock. Active excludes CLOSED_WON/CLOSED_LOST. Same member/known category reuses a lead; a sole unknown lead may be promoted to a known category; otherwise a different service creates a separate lead. Unknown with zero active leads creates canonical `unknown`; with one continues it; with multiple raises ambiguity and fails closed. The legacy `b2c_get_or_create_active_lead` remains present; its presence does not restore the superseded one-lead rule.

M lines 2534/2538 define `b2c_one_active_lead_per_member_service` and `b2c_one_active_unknown_lead_per_member`. The former's actual predicate includes non-null categories; the separate unknown index enforces the canonical fallback. Do not infer removed legacy behaviour from index names alone.

`b2c_update_lead_from_ai` (M line 1720) preserves human-follow-up state and guards known category changes. After handoff beyond NEW/AI_COLLECTING/READY_FOR_REVIEW, it advances receipt metadata and emits `AI_UPDATE_SKIPPED` / `HUMAN_OWNED_LEAD_STATE` rather than changing human-owned facts. Its internal updater `b2c_update_lead_from_ai_v1_internal` is also present. Presence does not independently establish all API privilege guarantees.

`b2c_list_active_lead_contexts` (M line 1403) returns structured active leads, including service details, scheduling, CCSV, distinct appointments and missing information; singular `b2c_get_active_lead_context` also exists (line 476). S3 Step 36 establishes latest customer message + active contexts as extraction input. Normalized 48-hour history remains audit/context material rather than direct extraction input. Workflow prompt wiring is **RECORD-SOURCED**, not stored in this repo.

## Structured extraction and normalization

S3 Steps 30–34, **RECORD-SOURCED**:

| Service | Verified historical structured fields |
|---|---|
| Meal Delivery | `meal_types`, `meal_periods`, `delivery_days`, `dietary_requirements`, `frequency` |
| Home Care | `care_requirements`, `service_days`, `time_periods`, `frequency`, `service_duration` |
| Home Cleaning | `cleaning_requirements`, `property_size`, `service_type`, schedule/frequency/duration |
| Physiotherapy | Explicit `physiotherapy_requirements`, district, service user, schedule/duration |
| Medical Escort | Pickup district/location, escort requirements, return-trip requirement, `medical_appointment.date/date_raw/time/location` |

Build Final Output deterministically normalizes time periods: 朝早/早上 → 上午, 下晝 → 下午, 夜晚 → 晚上 (S3 Step 32, RECORD-SOURCED).

Historical duration normalization examples are 2個鐘 → 2小時, 半個鐘 → 30分鐘, 個半鐘 → 1.5小時 (S3 Step 31, RECORD-SOURCED). The source does not directly identify their implementation node; these mappings are not attributed to Build Final Output.

拎藥/攞藥 → 取藥. Relative medical dates use customer-message timestamp + Asia/Hong_Kong + date_raw, not AI date arithmetic. Appointment date/time stays in medical_appointment, separate from preferred start/time and company follow-up appointment.

These workflow implementations are not present in SQL. S4's complete natural-time ambiguity behaviour is approved design; S3's relative-date tests do not prove every natural date/time parser case.

## Verified repository object inventory

M contains tables `b2c_staff_users` (2460), `b2c_leads` (1123), `b2c_lead_events` (2418), `b2c_inbound_messages` (2397), `b2c_service_blackout_dates` (2447).

`b2c_meal_delivery_date_available` (1582) rejects Sunday and active matching blackout dates. Calendar population and outbound integration are **NOT YET VERIFIED**; schema-only SQL does not supply holiday rows.

Additional captured references: `b2c_is_lead_ready_for_review` (1175); `b2c_get_current_staff_context` (585); dispatcher queue/detail/current-dispatcher assignment RPCs (748, 673, 427); `b2c_get_active_sales_users_as_current_dispatcher` (550). Status, assigned-Sales and next-follow-up indexes exist (2522–2530). Their presence proves definitions, not live UI acceptance or a follow-up engine.

## APPROVED DESIGN ONLY / NOT YET VERIFIED

Step 40A adaptive Smart Buttons, deterministic button updates, updated customer-facing choices, non-medical escort storage and wound-care conditional logic are approved; WOZTELL payload encoding, implementation and live acceptance are not established. See [product authority](../product/SALES_ENQUIRY_PRODUCT_SPEC.md).

The SQL service-category constraint (1167) still permits `ccsv`/`elderly_support` alongside current categories. **Stopped claim:** Step 40A product vocabulary is fully enforced by this baseline. Legacy vocabulary must not be silently deleted or presented as current business policy.

B10 assets are missing from this checkout; this public schema snapshot is not a complete current deployed security baseline. Refer to its record-sourced frozen contract without assuming activation.
