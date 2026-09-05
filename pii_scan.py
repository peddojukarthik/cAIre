"""
Lightweight PII/PHI pattern scanner.

Compensating control for the absence of Cloud DLP (which requires a full GCP
billing account). This is deliberately documented as WEAKER than DLP: DLP
uses trained ML detectors and a large library of built-in infoTypes; this
module is regex-based and will miss anything that doesn't match a known
pattern. It is a safety net for logs and OCR text before storage, not a
substitute for the RLS-based access control that is the primary security
boundary.

Use: before writing raw_ocr_text to logs (never to the DB column itself,
which needs the real text for extraction), pass it through `redact_for_log`.
"""

import re

_PATTERNS = {
    "aadhaar_like": re.compile(r"\b\d{4}\s?\d{4}\s?\d{4}\b"),
    "phone_in": re.compile(r"\b(?:\+91[\-\s]?)?[6-9]\d{9}\b"),
    "email": re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b"),
    "pan_card": re.compile(r"\b[A-Z]{5}\d{4}[A-Z]\b"),
}


def redact_for_log(text: str) -> str:
    """
    Returns a copy of `text` with likely PII patterns replaced by a labeled
    placeholder, safe to write to application logs or error trackers.
    Never used to sanitize data before it goes into extracted_findings --
    that pipeline needs the real values.
    """
    redacted = text
    for label, pattern in _PATTERNS.items():
        redacted = pattern.sub(f"[REDACTED:{label}]", redacted)
    return redacted


def contains_likely_pii(text: str) -> bool:
    return any(pattern.search(text) for pattern in _PATTERNS.values())
