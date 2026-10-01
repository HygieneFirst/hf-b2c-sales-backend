# Sales Enquiry Product Spec

Approved business/product authority reconstructed 2026-09-30. Sources: S4 §§4–6, 9, 13 and handoff block; S3 §4 for confirmed Sales handoff principles. [Source register](../project/PROJECT_MASTER_RECORD.md#authority-and-source-register). All approvals are **RECORD-SOURCED**. Implementation and acceptance are separately tracked in the [acceptance baseline](../acceptance/IMPLEMENTED_AND_VERIFIED_BASELINE.md).

## Approved services and classification

| Category | Customer-facing service |
|---|---|
| `meal_delivery` | Meal Delivery |
| `home_care` | Home Care |
| `home_cleaning` | Home Cleaning |
| `physiotherapy` | Physiotherapy |
| `wound_care` | Wound Care |
| `medical_escort` | 陪診／陪同外出 |
| `other` | Explicitly selected other service |

`unknown` means the service has not been identified; it is a system fallback, not the customer's explicit choice of other service. `elderly_support` is not a formal service item. CCSV is funding/case context, recorded separately as related/status while the primary category remains the actual requested service. Complex CCSV cases require human handoff; full application guidance is deferred.

## Adaptive collection and handoff

- Collect what the customer has already provided; do not ask known information again. Ask only genuinely missing information, rather than a fixed long questionnaire.
- Closed choices use Smart Buttons; complex/open information uses free text and AI extraction. A selected button value determines the field update and must not be reinterpreted by AI.
- Customers may request a human at any time. Reaching READY_FOR_REVIEW allows early handoff; READY_FOR_REVIEW does not require every field to be complete. A complete approved service-by-service readiness matrix is not supplied here and must not be invented.
- Customer requests/preferences are distinct from confirmed availability.
- Confirmed Sales process: AI intake → lead record → dispatcher review → dispatcher assigns Sales → Sales follow-up. S3 names Eva as dispatcher and Alex/Cathy as Sales in that historical operational context; those names do not authorize hardcoded access or assignment. AI does not assign a salesperson. An existing human-follow-up requirement must not be downgraded by AI.

## Service-specific rules

### Meal Delivery

Approved meal choices: 正常餐、糖尿餐、素食餐、碎餐、軟餐／糊餐、其他. 糊餐 has canonical value 軟餐; 糖尿餐 supersedes 三高餐. Dietary requirements are 忌口備註.

Delivery is Monday–Saturday; Sunday and Hong Kong public holidays are unavailable. Holiday availability is determined by the backend blackout calendar, not guessed by AI. A requested delivery day is not a confirmed booking or availability result.

### Home Care

Collect explicitly described care needs and scheduling preferences. Actual minimum/package duration is **NOT YET APPROVED** in the supplied current authority; extraction examples are not commercial package rules.

### Home Cleaning

Duration choices: 2小時、3小時、4小時、其他、未決定. Do not proactively offer a one-hour button. A customer-entered one-hour request may be recorded as a request; it does not establish service availability.

### Physiotherapy

Collect the customer's explicit functional difficulties and rehabilitation goals. AI must not diagnose, infer disease, recommend treatment or judge treatment suitability. Formal duration choices are **NOT YET APPROVED**.

### 陪診／陪同外出

Destinations may include hospitals, clinics, banks, government departments or other specified locations. Journeys may be one-way or return. Medical journey appointment information is distinct from company/Sales follow-up appointments. Non-medical destination/purpose information must not be represented as a medical appointment.

### Wound Care

Collect date, time, district and a free-text description of the wound-care need. General wound care/dressing changes do not require dressing instructions. Stitch removal requires dressing instructions; missing or unclear instructions require human follow-up.

AI must not diagnose, judge infection, advise treatment or recommend clinical frequency. Minimum duration and Sunday/public-holiday availability are **NOT YET APPROVED**.

## Natural time

Accept informal Chinese, full-width characters, punctuation and numeric formats; customers need not enter HH:MM. Normalize input and resolve time deterministically. AM/PM ambiguity requires clarification; AI must not guess the final canonical time. Approval of this behaviour does not prove the complete parser is implemented.

## Unapproved and excluded

Final FAQ/KB content and outbound reply policies are **NOT YET APPROVED** by these sources. Eric's pilot thresholds, question counts, sample size and timeline remain proposals. Earlier meal/service vocabulary and unconditional wound-care instruction rules are superseded by the rules above. No booking guarantee, pricing, package policy, new CRM scope or follow-up policy is inferred.
