# cAIre — Architecture

## Stack

| Layer | Choice | Why |
|---|---|---|
| Frontend | Plain HTML/JS, static | Fast to ship, no build step, served by Vercel |
| Backend | FastAPI (Python), running as a single Vercel serverless function (ASGI) | Async, typed; deployed via `@vercel/python` with no per-route rewrite |
| Database | Supabase (Postgres + pgvector) | Free tier, no card required; same engine as originally planned for Cloud SQL, so the schema and RLS design carry over unchanged |
| Auth | Supabase Auth | Free tier, no card required; standard JWTs verified server-side |
| File storage | Supabase Storage | Per-patient bucket paths, same role as Cloud Storage would have played |
| OCR + extraction | Google AI Studio Gemini (multimodal) | Gemini reads the uploaded PDF/image directly and returns structured findings in one call — no separate OCR service needed |
| AI (extraction / chat / summary) | Google AI Studio Gemini API | Free-tier API key, no GCP project or billing account required |
| Signing | App-level ECDSA-P256 (`app/services/signing.py`) | Same algorithm as the SIH project's hash-chain signing; private key lives in a Vercel encrypted environment variable |
| Secrets | Vercel Environment Variables | Encrypted at rest by Vercel; never in source control |
| PII/PHI safety net | Custom regex-based scan (`app/services/pii_scan.py`) | Compensating control for logs, in place of Cloud DLP |
| Embeddings | Gemini embedding model | Stored as pgvector rows in Supabase |
| Deploy | Vercel | Organiser-approved deployment target; no billing card required for either Vercel or Supabase free tiers |

## Why this stack, given the constraints

The original design used Cloud SQL, Cloud KMS, Cloud DLP, and Document AI —
all genuinely stronger, managed-service versions of what's built here. Two
real constraints changed that: the event organiser explicitly permits Vercel
deployment, and GCP's signup requires a card even for its free trial, which
wasn't acceptable. Supabase and Vercel's free tiers require no card at all.

What did **not** change: the actual security design. Patient isolation via
Postgres Row-Level Security, the provenance model (user-provided vs
ai-extracted vs ai-generated), and — most importantly — the rule that
reference ranges are read from the source document and never invented, are
all properties of the data model and pipeline logic, not of any particular
cloud vendor. Those survive the platform switch untouched.

What **did** get replaced with an application-level equivalent, and should
be stated plainly rather than glossed over in any write-up:

- **Cloud KMS → app-level ECDSA signing.** Cloud KMS never exposes a private
  key to application code, even to the app itself; here the key is an
  encrypted Vercel environment variable, which is a weaker but still
  meaningful guarantee (it prevents casual exposure via source control or
  logs, but not a compromise of the Vercel project itself).
- **Cloud DLP → regex-based PII scan.** DLP uses trained ML detectors across
  a large library of PII types; the scan here only catches patterns it has
  an explicit regex for (Aadhaar-shaped numbers, Indian phone numbers,
  emails, PAN numbers). It's a safety net for what gets written to logs, not
  the primary access-control boundary — that role is filled by RLS.
- **Document AI → Gemini multimodal.** Functionally this is arguably a
  simplification rather than a downgrade: one model call does OCR and
  structuring together, with one fewer service in the pipeline to secure and
  monitor.

## Data flow (file upload → insight)

```
Upload (Supabase Storage, per-patient path)
        │
        ▼
Gemini (multimodal): read PDF/image directly → raw text + structured draft
        │
        ▼
Regex PII scan → redacted copy used for any logging
        │
        ▼
SHA-256 hash → app-level ECDSA sign → documents row (versioned, chained)
        │
        ▼
Gemini: structure into extracted_findings rows
        │  (finding_type, value, unit, ref_range AS PRINTED ON THE DOCUMENT)
        ▼
Deterministic code: compare value to ref_range → flag LOW/NORMAL/HIGH
        │  (never an LLM call — this is the "don't invent reference ranges" guarantee)
        ▼
Deterministic SQL: find prior findings of same finding_type → compute delta
        │
        ▼
Gemini: narrate the delta + flag anomalies (e.g. medication vs. unrelated findings)
        │  → ai_insights row, source_finding_ids links back to evidence
        ▼
Gemini embeddings → finding_embeddings (pgvector) → available to RAG chat
```

## Why reference ranges still can't be invented

Unchanged from the original design, because this was never GCP-specific:

1. `extracted_findings.ref_range_low/high` are populated only from what
   Gemini reads in the source document's own text (`ref_range_source_text`
   stores the verbatim printed string for audit).
2. If a document has no printed range, these columns stay `NULL`.
3. The LOW/NORMAL/HIGH flag is computed by a plain comparison function in
   application code — never by asking the model "is this high?" — so there
   is no step where the model could substitute a hallucinated or
   general-population range for the one on the actual report.

## Provenance model

Unchanged: every table that can hold AI-touched data carries a `provenance`
enum (`user_provided` / `ai_extracted` / `ai_generated`), rendered in the UI
with distinct visual treatment so a user can always tell what they typed
versus what the system extracted or generated.

## Patient isolation (security boundary)

- Every patient-scoped table has Postgres Row-Level Security enabled,
  running on Supabase's Postgres exactly as it would have on Cloud SQL.
- The backend never issues a request-scoped query without first setting
  `app.current_user_id` from a **verified** Supabase JWT (see
  `app/core/auth.py` and `app/core/db.py`).
- A bug that forgets a `WHERE patient_id = ...` clause in a route handler
  still cannot leak another patient's rows — the database itself refuses to
  return them.

## Responsible AI guardrails

- System prompts for all Gemini calls explicitly instruct: describe findings
  and trends, never diagnose, never recommend medication or dosage changes.
- Every AI-generated insight carries `disclaimer_shown = true` and is
  rendered with a persistent "informational only, not medical advice" banner.
- Anomaly detection (e.g. a prescription unrelated to recent findings) is
  phrased as "this looks inconsistent — consult a doctor," never as a
  clinical judgment about the medication's correctness.

## Still to build

2. Auth + patient intake (Supabase Auth wiring, intake form)
3. File upload pipeline (Gemini multimodal extraction → signing → flagging)
4. Comparison engine + narrative summaries
5. RAG chat
6. Frontend
7. Security write-up finalized (this doc) + `.gitignore` covering the private signing key
