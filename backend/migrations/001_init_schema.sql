-- cAIre: Core schema
-- Target: Cloud SQL for PostgreSQL 15+
-- Design principles enforced by this schema:
--   1. Row-Level Security (RLS) on every patient-scoped table -> hard isolation
--      boundary, not just an application-layer WHERE clause.
--   2. Every AI-touched field carries a provenance flag + confidence score,
--      so the UI can always distinguish user-entered vs extracted vs AI-generated.
--   3. Reference ranges are NEVER computed/invented in SQL or application logic
--      beyond what was extracted from the source document itself.
--   4. Append-only versioning on documents (superseded_by chain), mirroring
--      the hash-chain approach from the SIH project, adapted to single-tenant use.

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS vector;     -- pgvector, for RAG embeddings

-- ============================================================================
-- ENUM TYPES
-- ============================================================================

CREATE TYPE document_category AS ENUM (
    'lab_report',
    'prescription',
    'surgery_operative_note',
    'discharge_summary',
    'imaging_radiology',
    'vaccination_record',
    'general'
);

CREATE TYPE provenance_type AS ENUM (
    'user_provided',      -- typed directly by the patient
    'ai_extracted',        -- pulled from a document by Document AI / Gemini, verbatim
    'ai_generated'          -- synthesized/narrated by Gemini (summary, comparison, anomaly flag)
);

CREATE TYPE finding_flag AS ENUM ('low', 'normal', 'high', 'unflagged');

CREATE TYPE extraction_status AS ENUM (
    'pending', 'ocr_done', 'extracted', 'flagged', 'summarized', 'failed'
);

-- ============================================================================
-- PATIENTS  (one row per registered user; the user-provided source of truth)
-- ============================================================================

CREATE TABLE patients (
    patient_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supabase_user_id     UUID UNIQUE NOT NULL,          -- Supabase Auth identity (auth.users.id)
    full_name            TEXT NOT NULL,
    email                TEXT UNIQUE NOT NULL,
    phone_number         TEXT,

    -- Aadhaar: NEVER store the raw number. Only a salted hash (for uniqueness
    -- checks / re-verification) and the last 4 digits (for display).
    aadhaar_hash          TEXT UNIQUE,
    aadhaar_last4          CHAR(4),

    -- Baseline intake, captured at first login. All provenance = user_provided.
    date_of_birth         DATE,
    sex                    TEXT,
    height_cm              NUMERIC(5,2),
    weight_kg              NUMERIC(5,2),
    known_allergies        TEXT[],
    existing_conditions     TEXT[],
    current_symptoms       TEXT[],
    other_notes            TEXT,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE patients ENABLE ROW LEVEL SECURITY;

-- App connects as a role that sets app.current_user_id per request (a Supabase auth.uid())
-- (see backend/app/core/db.py). This policy ensures a patient can only ever
-- see/modify their own row, enforced at the database layer, not just in code.
CREATE POLICY patient_self_access ON patients
    USING (supabase_user_id = current_setting('app.current_user_id', true)::uuid);

-- ============================================================================
-- EPISODES  (groups documents belonging to one clinical thread, e.g. one surgery)
-- ============================================================================

CREATE TABLE episodes (
    episode_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id        UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    label              TEXT NOT NULL,             -- e.g. "Right knee replacement, 2026"
    episode_type        TEXT,                       -- surgery / chronic_condition / acute_illness / general
    started_on          DATE,
    notes               TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE episodes ENABLE ROW LEVEL SECURITY;
CREATE POLICY episode_owner_access ON episodes
    USING (patient_id IN (
        SELECT patient_id FROM patients
        WHERE supabase_user_id = current_setting('app.current_user_id', true)::uuid
    ));

-- ============================================================================
-- DOCUMENTS  (one row per uploaded file; hashed, signed, versioned)
-- ============================================================================

CREATE TABLE documents (
    document_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id             UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    episode_id              UUID REFERENCES episodes(episode_id) ON DELETE SET NULL,

    category                document_category NOT NULL,
    original_filename        TEXT NOT NULL,
    storage_path             TEXT NOT NULL,          -- gs://bucket/patient_id/document_id
    mime_type                TEXT,

    -- Integrity & provenance chain (mirrors SIH hash-chain versioning)
    sha256_hash              TEXT NOT NULL,
    kms_signature             TEXT NOT NULL,           -- signature over sha256_hash, via Cloud KMS
    kms_key_version            TEXT NOT NULL,
    version_number             INT NOT NULL DEFAULT 1,
    supersedes_document_id      UUID REFERENCES documents(document_id),

    document_date              DATE,                    -- date ON the report itself (critical for trend ordering)
    upload_timestamp             TIMESTAMPTZ NOT NULL DEFAULT now(),

    raw_ocr_text                TEXT,                    -- Document AI output, DLP-redacted copy for logs only
    status                      extraction_status NOT NULL DEFAULT 'pending',
    extraction_error             TEXT,

    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_documents_patient_date ON documents(patient_id, document_date);
CREATE INDEX idx_documents_episode ON documents(episode_id);

ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY document_owner_access ON documents
    USING (patient_id IN (
        SELECT patient_id FROM patients
        WHERE supabase_user_id = current_setting('app.current_user_id', true)::uuid
    ));

-- ============================================================================
-- EXTRACTED_FINDINGS  (atomic data points pulled from a document by Gemini)
-- One row per test/value/observation -> makes trend queries a simple filter,
-- not a document-diffing exercise.
-- ============================================================================

CREATE TABLE extracted_findings (
    finding_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id          UUID NOT NULL REFERENCES documents(document_id) ON DELETE CASCADE,
    patient_id            UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,

    finding_type           TEXT NOT NULL,      -- normalized key, e.g. 'blood_pressure_systolic', 'hba1c'
    display_name            TEXT NOT NULL,      -- as printed on the report, e.g. "Systolic BP"

    value_numeric             NUMERIC,
    value_text                 TEXT,             -- for non-numeric observations
    unit                        TEXT,

    -- Reference range: ONLY ever populated from what appears in the source
    -- document. If the document has no range, these stay NULL and flag = 'unflagged'.
    -- This column pair is the enforcement point for "never invent a reference range."
    ref_range_low               NUMERIC,
    ref_range_high               NUMERIC,
    ref_range_source_text         TEXT,           -- verbatim range string as printed, for auditability

    flag                          finding_flag NOT NULL DEFAULT 'unflagged',   -- computed deterministically, not by LLM

    provenance                    provenance_type NOT NULL DEFAULT 'ai_extracted',
    extraction_confidence           NUMERIC(4,3),   -- 0.000-1.000, from Gemini's self-reported confidence

    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_findings_patient_type_date ON extracted_findings(patient_id, finding_type);
CREATE INDEX idx_findings_document ON extracted_findings(document_id);

ALTER TABLE extracted_findings ENABLE ROW LEVEL SECURITY;
CREATE POLICY finding_owner_access ON extracted_findings
    USING (patient_id IN (
        SELECT patient_id FROM patients
        WHERE supabase_user_id = current_setting('app.current_user_id', true)::uuid
    ));

-- ============================================================================
-- AI_INSIGHTS  (summaries, trend narratives, anomaly flags -- always linked
-- back to the specific findings/documents that produced them)
-- ============================================================================

CREATE TABLE ai_insights (
    insight_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id              UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    document_id              UUID REFERENCES documents(document_id) ON DELETE CASCADE,  -- nullable: some insights span multiple docs

    insight_type               TEXT NOT NULL,     -- 'summary' / 'trend_comparison' / 'anomaly_flag'
    title                        TEXT NOT NULL,
    body                          TEXT NOT NULL,
    severity                      TEXT DEFAULT 'info',   -- info / attention / consult_doctor

    -- Explicit provenance links: which findings fed this insight. Enables the
    -- "side-by-side source vs structured info" UI requirement.
    source_finding_ids               UUID[],

    provenance                        provenance_type NOT NULL DEFAULT 'ai_generated',
    model_name                         TEXT,             -- e.g. 'gemini-2.5-pro'
    disclaimer_shown                    BOOLEAN NOT NULL DEFAULT true,

    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_insights_patient ON ai_insights(patient_id, created_at DESC);

ALTER TABLE ai_insights ENABLE ROW LEVEL SECURITY;
CREATE POLICY insight_owner_access ON ai_insights
    USING (patient_id IN (
        SELECT patient_id FROM patients
        WHERE supabase_user_id = current_setting('app.current_user_id', true)::uuid
    ));

-- ============================================================================
-- FINDING_EMBEDDINGS  (RAG vector store for the 24/7 chat)
-- ============================================================================

CREATE TABLE finding_embeddings (
    embedding_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id             UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    source_type              TEXT NOT NULL,     -- 'finding' / 'insight' / 'document_summary'
    source_id                 UUID NOT NULL,      -- FK into extracted_findings.finding_id or ai_insights.insight_id
    chunk_text                 TEXT NOT NULL,      -- text that was embedded
    embedding                    vector(768),        -- Vertex AI text-embedding-004 dimension
    created_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_embeddings_patient ON finding_embeddings(patient_id);
CREATE INDEX idx_embeddings_vector ON finding_embeddings
    USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

ALTER TABLE finding_embeddings ENABLE ROW LEVEL SECURITY;
CREATE POLICY embedding_owner_access ON finding_embeddings
    USING (patient_id IN (
        SELECT patient_id FROM patients
        WHERE supabase_user_id = current_setting('app.current_user_id', true)::uuid
    ));

-- ============================================================================
-- CHAT_MESSAGES  (24/7 chat history, per patient)
-- ============================================================================

CREATE TABLE chat_messages (
    message_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id            UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    role                    TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content                  TEXT NOT NULL,
    retrieved_finding_ids      UUID[],   -- which findings were pulled into context for this turn (auditability)
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_chat_patient_time ON chat_messages(patient_id, created_at);

ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_owner_access ON chat_messages
    USING (patient_id IN (
        SELECT patient_id FROM patients
        WHERE supabase_user_id = current_setting('app.current_user_id', true)::uuid
    ));

-- ============================================================================
-- AUDIT_LOG  (application-level audit trail, complements Cloud Audit Logs)
-- ============================================================================

CREATE TABLE audit_log (
    audit_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id           UUID REFERENCES patients(patient_id) ON DELETE SET NULL,
    actor_user_id          UUID,
    action                  TEXT NOT NULL,        -- 'document_upload' / 'document_view' / 'chat_query' / 'export' / 'login'
    resource_type            TEXT,
    resource_id                UUID,
    metadata                   JSONB,
    ip_address                  INET,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_patient_time ON audit_log(patient_id, created_at DESC);

-- No RLS on audit_log by patient policy -- it is written by the backend
-- service account only and never queried directly by patient-scoped sessions
-- except via a dedicated /timeline endpoint that filters explicitly.
