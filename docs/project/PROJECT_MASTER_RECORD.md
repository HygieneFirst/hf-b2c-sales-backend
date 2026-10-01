# Project Master Record

Reconstructed 2026-09-30. This is historical lineage and project-state context; detailed authorities are linked below. No deployment or database operation was performed during reconstruction.

## Authority and source register

Implementation evidence takes precedence for actual implementation state; frozen architecture/security contracts govern technical obligations; approved business decisions govern product behaviour; acceptance evidence governs PASS claims. Historical proposals do not become requirements. Design approval does not establish implementation, and implementation does not establish business acceptance.

Source IDs refer to supplied records, not executable instructions:

| ID | Supplied filename | Authority |
|---|---|---|
| S1 | `01_工作步驟建議_Historical_Decision_Milestone_Extraction.md` | Initial mandate and confirmed channel clarification |
| S2 | `02_覆Eric英文建議_Historical_Decision_Milestone_Extraction.md` | Management framing and unapproved pilot history |
| S3 | `03_Sales_Enquiry自动化方案_Historical_Decision_Milestone_Extraction.md` | Historical implementation/verification authority for Steps 30–38 |
| S4 | `04_驗證準備規則_Final_Handover_Record.md` | Step 39 final handover and Step 40A design approval |
| S5 | `05_AI指令盤點_Final_Handover_Record_B10_PRIMARY.md` | Primary B10 / R1-01G / G4.6L frozen handover |
| S6 | `06_整理项目进度_Final_Handover_Record_B10_CORROBORATING.md` | B10 corroboration only; no independent B10 authority |

The supplied files were read from the user's Downloads folder. They are not archived in this repository. Their original conversation evidence, review PDF and B10 execution package were not available here. Source IDs and section numbers preserve attribution; reconstruction does not invent original evidence.

**VERIFIED AGAINST REPO** means checked against this checkout/history, not today's hosted deployment. **RECORD-SOURCED** means preserved from the specified supplied record without independent verification. Missing evidence is not a negative finding about deployment.

## Original mandate and evolution

S1 §§2–4 confirms Recruitment WhatsApp Automation, Sales/Customer Enquiry WhatsApp Automation and a Small CRM covering workers and enquiry leads, classification, stages, Sales assignment and basic follow-up records. Recruitment and Enquiry use two separate phone numbers ([ADR-001](../decisions/ADR-001-two-whatsapp-business-channels.md)). S1 establishes no implemented or accepted CRM/recruitment system.

S2 records management concern about extending WhatsApp work into ERP/Drive analysis. The accepted working direction was to investigate discrepancies between system-visible evidence and undocumented operational logic before deciding system replacement. ERP was not proven the main cause. Eric's detailed WhatsApp pilot remained proposed: its response targets, completion/handoff percentages, sample size, timeline and named automatic routing are not approved product requirements.

S3 records the subsequent Sales Enquiry implementation and controlled/live verification. S4 establishes database history adoption and later product design approval. S5 closes the private backend/security workstream. Each record's end-of-chat state is local to that historical phase.

## Milestone sequence

| Milestone | Recorded outcome | Primary home |
|---|---|---|
| Steps 30–34 | Structured service extraction and deterministic normalization verified | [System](../architecture/SALES_ENQUIRY_SYSTEM_BASELINE.md), [acceptance](../acceptance/IMPLEMENTED_AND_VERIFIED_BASELINE.md) |
| Step 35 | Member + service routing; isolation and category guard verified | [ADR-002](../decisions/ADR-002-lead-routing-by-member-and-service.md) |
| Step 36 | Active Lead Context replaces direct 48-hour transcript extraction | [ADR-003](../decisions/ADR-003-active-lead-context-over-48h-transcript.md) |
| Step 37 | Failure/retry and safe error handling verified; canonical unknown correction | Acceptance baseline |
| Step 38 | WOZTELL authenticity gate verified | System and acceptance baselines |
| Step 39 | PASS / COMPLETED / FROZEN | Acceptance baseline |
| Step 40A | APPROVED / COMPLETE; design acceptance only | [Product spec](../product/SALES_ENQUIRY_PRODUCT_SPEC.md) |
| B10 / R1-01G / G4.6L | PASS / FROZEN; hardening workstream CLOSED | [Security baseline](../architecture/B10_BACKEND_SECURITY_BASELINE.md) |

## Repository reconstruction evidence

Checkout: `D:\hf-b2c-sales-backend`, branch `main`, HEAD `f491fd3d946114861bb6ad3ef835bccc8813503c`; clean before documentation creation. VERIFIED AGAINST REPO:

- `25e4ca896b434f626847e6b2bb3fcc69076f4a9f` — establish B2C backend repository.
- `c019ddb2a3156cbc67c202308bfb9884a13059f6` — capture production Supabase schema baseline.
- `f491fd3d946114861bb6ad3ef835bccc8813503c` — establish production schema baseline migration.
- [Public snapshot](../../supabase/baseline/production_public_schema_20260922.sql) and [migration](../../supabase/migrations/20260922071000_production_baseline_20260922.sql) exist and match S4's hash/size.

Only the public baseline migration is present. There is no stored n8n export, B10 migration package, verification output or Smart Button review PDF. This checkout cannot independently reconstruct B10's private objects. No hosted inventory was performed. Local `supabase/config.toml` is not hosted configuration evidence.

The README still says a baseline is pending; that statement is stale relative to the committed baseline files. It was not edited under this ten-file scope.

## Supersession and unresolved alignment

The ADRs preserve superseded single-number routing, one-active-lead-per-member, direct transcript extraction, prompt-only normalization, Vault isolation and schema-local default-hardening assumptions. The product spec preserves Step 40A's later service/menu corrections.

**Stopped claim:** the approved customer-facing service set is already enforced by the production baseline. The SQL check at line 1167 still permits legacy `ccsv` and `elderly_support`; S4 explicitly anticipates legacy values. Product approval and captured implementation differ. No constraint deletion, prompt update or silent alignment is authorized.

## Next workstream

S4's then-next workstream was Step 40B Knowledge Base Current-State Inventory, with Step 40C–H reply policy, auto-reply, qualification, outbound, calendar integration and live acceptance deferred. S5/S6's latest handover names **WhatsApp Sales Enquiry Thin Vertical Slice / End-to-End Pilot** as an independent next workstream. Its implementation details and timing are not frozen here. The records do not establish how Step 40B–H map into that pilot.

B10 is closed; do not create B11/B12 infrastructure scope. Real bootstrap still requires independent, explicit authorization. Recruitment, a new CRM, follow-up engine, FAQ/KB contents, prompt specification and Smart Button implementation are outside this reconstruction.
