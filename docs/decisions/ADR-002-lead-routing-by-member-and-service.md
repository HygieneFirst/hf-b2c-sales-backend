# ADR-002 — Lead routing by member and service category

## Status

IMPLEMENTED / VERIFIED historically, S3 Step 35. SQL routing/index definitions VERIFIED AGAINST REPO; controlled/live tests RECORD-SOURCED.

## Context

One active lead per member merged Meal Delivery and Medical Escort information, leaving cross-service fields on the same lead.

## Decision

Route by member + service category: same known service reuses its active lead; different services have separate active leads. Unknown continuation is permitted only when unambiguous; multiple active leads with unidentified service fail closed. Known categories cannot be changed to another known service by AI. Exact captured routing, including unknown promotion, is owned by the system baseline.

## Why

Service isolation prevents cross-enquiry pollution while preserving multi-turn continuation. Ambiguity must not cause an arbitrary lead selection.

## Supersedes

`b2c_one_active_lead_per_member` / one-active-lead-per-member. NULL as stored uncategorized category is superseded by canonical `unknown`; internal parameter normalization is not a stored NULL policy.

## Do not reopen unless

An approved routing change includes explicit service-isolation and ambiguity acceptance criteria, or verified evidence contradicts the captured routing. Do not remove isolation merely to simplify intake.

## References

S3 Steps 35–37; [system baseline](../architecture/SALES_ENQUIRY_SYSTEM_BASELINE.md#lead-routing-and-context); [acceptance](../acceptance/IMPLEMENTED_AND_VERIFIED_BASELINE.md). VERIFIED AGAINST REPO: migration `20260922071000`, `b2c_get_or_create_active_lead_v2` line 809, update guard line 1720, indexes lines 2534/2538. Historical smoke outcomes remain RECORD-SOURCED.
