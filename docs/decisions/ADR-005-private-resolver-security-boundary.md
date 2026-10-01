# ADR-005 — Private resolver security boundary

## Status

B10 / R1-01G / G4.6L PASS / FROZEN; security hardening CLOSED. S5 is primary authority; S6 corroborates. All physical/configuration verification is RECORD-SOURCED, not independently reproduced from this checkout.

## Context

Runtime service_role transport access cannot constitute independent resolver authority. Existing Vault capabilities did not isolate resolver secret material from that runtime. PostgreSQL schema-local function default privilege revocation also failed to supply the proposed automatic hardening guarantee.

## Decision

Preserve the postgres-owned `b2c_private` key/secret/replay boundary and independent cryptographic resolver authority. Runtime access is closed. Preserve the frozen lifecycle, reconciliation and function security contract in the B10 baseline. B14-5C Model B requires governed same-transaction ACL closure, full-schema pre-COMMIT assertions and post-DDL verification for private-function changes; it authorizes no database-wide default privilege alteration.

## Why

The private boundary separates transport credentials from resolver decision authority. Model B addresses the demonstrated compatibility limitation without expanding default-privilege blast radius. Trusted postgres remains an administrative exception, not a runtime alternative.

## Supersedes

Vault as independent resolver HMAC isolation; caller-settable GUC as trusted mutation-origin proof; schema-local default-privilege revoke as automatic hardening. Database-wide revoke was a candidate, not adopted or authorized. Generic/idempotent RETIRE/DESTROY mutation shortcuts are not the frozen contract. Earlier migration assertions and verification packs are superseded by reviewed R3 migration/R7 verification.

## Do not reopen unless

An independently approved security/compatibility review explicitly amends the frozen contract, or verified implementation evidence directly contradicts it. B10 completion does not authorize bootstrap, signing credential provisioning or gateway activation; those require their separate gates. Do not create B11/B12 infrastructure scope from this reconstruction.

## References

S5 §§4–9, 13–14; S6 corroboration. [B10 security authority](../architecture/B10_BACKEND_SECURITY_BASELINE.md), [acceptance lineage](../acceptance/IMPLEMENTED_AND_VERIFIED_BASELINE.md). `001_b14_private_security_infrastructure.sql`, `003_post_ddl_b10_verification.sql` R7 and `B10_POST_DDL_VERIFICATION_RESULTS_R7.txt` are RECORD-SOURCED and absent from the repository; no B10 commit/tag is verified.
