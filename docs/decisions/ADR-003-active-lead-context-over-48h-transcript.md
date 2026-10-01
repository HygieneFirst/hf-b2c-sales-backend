# ADR-003 — Active Lead Context over direct 48-hour transcript extraction

## Status

IMPLEMENTED / VERIFIED historically; S3 Step 36. Context RPC VERIFIED AGAINST REPO; extraction wiring/tests RECORD-SOURCED.

## Context

Directly feeding a 48-hour conversation transcript into extraction mixed multiple service enquiries for the same customer.

## Decision

Extraction uses Latest Customer Message + Supabase Active Lead Contexts. Normalized conversation history may remain an audit/context source; it is not directly substituted for structured active contexts in extraction.

## Why

Service-specific existing facts enable short continuation messages without importing another enquiry's requirements. S3 records successful same-lead continuation and separate-service isolation.

## Supersedes

Direct `current_session_transcript` / 48-hour-gap history feeding Lead Extraction. The existence of history-fetch nodes does not reinstate the old input model.

## Do not reopen unless

An approved context model change demonstrates multi-service isolation and unambiguous continuation through acceptance evidence, or stored workflow evidence contradicts the recorded implementation.

## References

S3 Step 36 and §8; [system baseline](../architecture/SALES_ENQUIRY_SYSTEM_BASELINE.md#lead-routing-and-context); [acceptance](../acceptance/IMPLEMENTED_AND_VERIFIED_BASELINE.md). VERIFIED AGAINST REPO: `b2c_list_active_lead_contexts` in baseline migration line 1403. `Supabase - Get Active Lead Contexts` and workflow `Osa86r7Ehpo2b1y7` are RECORD-SOURCED; no export is stored.
