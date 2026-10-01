# ADR-001 — Two separate WhatsApp business channels

## Status

CONFIRMED business decision; RECORD-SOURCED from S1 §§3–4, 8. No channel deployment acceptance is implied.

## Context

The initial mandate included Recruitment automation and Customer Enquiry automation. An early interpretation used one number and intent detection to route both populations.

## Decision

Recruitment and Customer Enquiry use two separate WhatsApp phone numbers. Each channel determines its business use case.

## Why

The user explicitly clarified that one phone is for Recruitment and one is for Enquiry. Top-level AI classification between those two purposes is unnecessary under that requirement.

## Supersedes

The proposed single-number Recruitment/Enquiry intent router. Shared CRM/database architecture was merely proposed and is not established by this decision.

## Do not reopen unless

An explicit approved business change alters the two-number requirement. Implementation convenience alone is insufficient.

## References

[Source register and mandate](../project/PROJECT_MASTER_RECORD.md). S1 confirmed clarification; no repo channel configuration was available. All channel references are RECORD-SOURCED.
