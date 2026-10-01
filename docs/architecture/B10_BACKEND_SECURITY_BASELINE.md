# B10 Backend / Security Baseline

**R1-01G / G4.6L — PASS / FROZEN. Supabase / Database / Security Hardening workstream CLOSED.**

Primary authority: S5 §§3–9, 13–14 and handoff block. S6 corroborates only. [Source register](../project/PROJECT_MASTER_RECORD.md#authority-and-source-register). Every B10 physical/deployed claim in this document is **RECORD-SOURCED**: no B10 SQL, results file or private schema is present in this checkout, and no live query was performed. Historical acceptance remains frozen; the checkout's missing package does not contradict reported execution. Exact unsupplied contract details must not be invented.

## Frozen authority boundary

`b2c_private`, owned by `postgres`, is the independent resolver key/secret/replay boundary. Vault isolation was rejected because existing service_role Vault capabilities did not satisfy the threat model. Runtime transport may use n8n service_role to call a public gateway under the frozen model; service_role transport access is not resolver decision authority. Independent cryptographic proof is required. This contract does not establish an activated gateway.

Resolver protocol: `HF_B2C_RESOLUTION_V1`, HMAC-SHA256, exact UTF-8 payload bytes, 64 lowercase hex signature; no normalization or reserialization before verification. Resolver key material is exactly 32 cryptographically random raw bytes; administrative transfer form is exactly 64 lowercase hex. Encoded hex is not itself the raw HMAC key. This differs from WOZTELL inbound Base64 signature verification.

## Private physical objects and posture

Tables:

- `b2c_private.resolver_key_registry`: permanent identity/history; no delete; mutations limited to exact lifecycle progression.
- `b2c_private.resolver_hmac_secrets`: UPDATE prohibited; supported deletion only through governed destruction.
- `b2c_private.resolution_replay_ledger`: append-only.

PUBLIC, anon, authenticated, authenticator and service_role have no schema USAGE/CREATE, no private table/column access and no private function EXECUTE. Private objects/functions are postgres-owned. Private functions are SECURITY INVOKER, use the fixed approved search_path, deny PUBLIC/runtime EXECUTE and retain postgres administrative EXECUTE, unless separately approved exception. The supplied record does not specify the literal search_path; it must be recovered from the reviewed package before any future implementation review.

No unexpected overload, public wrapper, alias, proxy or alternate private mutation path is supported. R7 reviewed definitions/dependencies and found no private dynamic SQL, SET ROLE or generic dispatch, no private views/materialized views and no external frozen-name wrapper; global SECURITY DEFINER review reported no new blocker, not a claim that none exist anywhere.

Administrative interfaces (exact record-sourced signatures):

```text
b2c_private.bootstrap_resolver_key(text,bytea,jsonb)
b2c_private.reconcile_resolver_key_bootstrap(text,bytea)
b2c_private.retire_resolver_key(text,jsonb)
b2c_private.destroy_resolver_key(text,jsonb)
b2c_private.reconcile_resolver_key_lifecycle(text,text)
```

Helpers:

```text
b2c_private.guard_resolver_key_registry_mutation()
b2c_private.guard_resolver_hmac_secret_mutation()
b2c_private.guard_resolution_replay_history()
b2c_private.enforce_resolver_key_secret_final_state()
```

`resolution_replay_ledger_candidate_idx` is NON-UNIQUE on `(authentication_domain, verified_key_id, exact_payload_fingerprint)`. External FK target is `public.b2c_resolution_decisions(decision_id)`; that target is not present in the public snapshot here, so no local FK implementation claim is made.

## Lifecycle and reconciliation boundaries

Only ACTIVE → RETIRED → DESTROYED is supported; no reversal, jump, repair or idempotent mutation shortcut. RETIRE and DESTROY have separate entrypoints because preconditions, secret handling and effects differ.

Both registry-side and secret-side mutations trigger DEFERRABLE INITIALLY DEFERRED final-state consistency validation: ACTIVE and RETIRED require exactly one matching valid secret; DESTROYED requires none.

SQLSTATE `P13L1` is governed RETIRE/DESTROY rejection only before provisional success. It propagates unchanged, yields no provisional success row, requires ROLLBACK, and permits no COMMIT, retry or repair. Deferred/COMMIT-stage failures must not use P13L1.

If COMMIT was issued but its outcome is unknown: `LIFECYCLE_COMMIT_OUTCOME_UNKNOWN` → no blind retry → read-only reconciliation first. Lifecycle reconciliation's RETIRE/DESTROY discriminator interprets current state; it does not attribute a transaction. Bootstrap reconciliation result namespace remains:

```text
RECONCILIATION_EXACT_MATCH
RECONCILIATION_ABSENT
RECONCILIATION_CONFLICT
RECONCILIATION_INVALID_STATE
```

Exact nested retirement/destruction provenance vocabulary is not frozen in the supplied authority.

## B14-5C Model B — frozen compatibility amendment

**MODEL B — GOVERNED PRIVATE-FUNCTION CREATION CONTROL — PASS / CONTRACT FROZEN.** Schema-local default privilege revoke did not provide the required removal of global/hard-wired PUBLIC EXECUTE defaults. Model B supersedes only that impossible automatic-hardening assumption; all other ACL/security obligations remain.

Every reviewed migration creating, replacing or altering a b2c_private function must perform same-transaction explicit ACL closure, a full-schema pre-COMMIT function assertion, mandatory post-DDL verification and governed administrative review.

**No database-wide ALTER DEFAULT PRIVILEGES change is authorized.** Global postgres routine defaults remain unchanged. V19 ROW_COUNT = 0 is EXPECTED / INFORMATIONAL under Model B. This is a supported-process guarantee, not a physical restriction on trusted postgres owner capabilities.

## Administrative execution discipline

Approved path: trusted workstation → Python/pg8000 → authenticated TLS → PostgreSQL postgres. Secret input is hidden and does not pass through argv, environment, source or config; no real secret appears in migration SQL. S6 corroborates `log_parameter_max_length = 0` and `log_parameter_max_length_on_error = 0`.

Migration execution is one complete transaction; do not split statements, edit failed SQL in place for blind retry or bypass commit-uncertainty reconciliation. Post-DDL physical verification is mandatory before bootstrap eligibility.

## Migration and verification references

All names/hashes below are **RECORD-SOURCED, NOT PRESENT IN REPO**:

| Artifact | Recorded SHA-256 / role |
|---|---|
| `001_b14_private_security_infrastructure.sql` | Executed R3: `98eba677642ecb3405b0199c7fa7cee0ac694fc94a94c43ec75030c8ec82eb4a` |
| `002_pre_activation_rollback.sql` | `097d213849b1230ee6cffe0e29979ed89912feab1eddfb330d3604ed4424bc9f` |
| `003_post_ddl_b10_verification.sql` | R7: `bacd6b0d48ec29ca768d3e7b5ffd553493ad60607672aef7c73fe568778b792e` |
| `B10_POST_DDL_VERIFICATION_RESULTS_R7.txt` | Final V01–V19 results; original output unavailable |
| `004_B15_IMPLEMENTATION_NOTES.md` | Named by corroborating S6; unavailable |

No B10 repo commit/tag was established by the records. Acceptance/review lineage is maintained in the [acceptance baseline](../acceptance/IMPLEMENTED_AND_VERIFIED_BASELINE.md), rather than inferred from filenames.

## Data API closure and pre-bootstrap state

S5 records Dashboard public/graphql_public exposed, b2c_private NOT exposed, plus authoritative applicable authenticator/current-database persisted `pgrst.db_schemas` inventory with zero matches. Both gates produced B10-PGRST PASS / CLOSED. This was not rechecked against today's hosted settings. S6 records no change to the Automatically expose new tables toggle.

At final B10 acceptance: registry/secret/replay row counts were 0/0/0. This is a historical empty pre-bootstrap observation, not a live inventory. **B10 PASS does not authorize real bootstrap.**

Real key/secret provisioning, n8n signing credentials, public gateway/private recorder activation, runtime context issuance, lead binding, signed production traffic and legacy disable/cutover remain outside this closure. They cannot be assumed active. Bootstrap requires independent explicit authorization. Do not open B11/B12 infrastructure scope; the separate next workstream is Thin Vertical Slice / End-to-End Pilot.
