# ADR-004 — Deterministic Smart Button and normalization model

## Status

CONFIRMED deterministic normalization in S3 Steps 31–34; APPROVED DESIGN ONLY for Smart Button updates and full natural-time behaviour in S4 Step 40A. Workflow implementations/tests and approvals are RECORD-SOURCED.

## Context

Prompt-only normalization was inconsistent, including 下晝 time-period output. Closed-choice button selections already convey an exact value and do not require AI interpretation.

## Decision

Deterministic values and canonical normalization must not be reinterpreted by AI. Smart Button → deterministic field update; free text → AI extraction followed by applicable deterministic normalization. Ambiguous natural time requires clarification before canonical assignment. The product spec owns approved collection/menu behaviour; the system baseline owns historically implemented normalization examples.

## Why

Deterministic handling preserves explicit customer choices and avoids inconsistent canonical formats or guessed time meanings.

## Supersedes

Prompt-only normalization as the guarantee for fixed formats, and any proposed re-extraction of exact Smart Button payload values through AI. This decision does not supply a WOZTELL encoding or implementation design.

## Do not reopen unless

An explicitly approved business/technical change preserves exact choice semantics and resolves ambiguity with evidence. AI convenience does not justify reinterpreting explicit values.

## References

S3 Steps 31–34 and §4; S4 decisions 3–4/10 and §§7/9. [Product spec](../product/SALES_ENQUIRY_PRODUCT_SPEC.md), [system baseline](../architecture/SALES_ENQUIRY_SYSTEM_BASELINE.md#structured-extraction-and-normalization), [acceptance](../acceptance/IMPLEMENTED_AND_VERIFIED_BASELINE.md). No repo normalization code, Smart Button export or review PDF was available; all implementation references for this ADR are RECORD-SOURCED.
