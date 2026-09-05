# cAIre — AI-Powered Clinical Information Intelligence

cAIre organizes scattered patient information and medical reports into a structured, reviewable patient record.

## Problem
Patient information may be spread across histories, prescriptions, laboratory reports and previous records. cAIre brings available information together for easier review.

## Core Features
- Patient information intake
- Medical report upload
- Structured test/value/unit/reference-range information
- Low / Normal / High classification using ranges supplied by the source report
- Source and provenance labels
- Patient-friendly AI summary
- Responsible-AI safety messaging

## Reference-Range Safety
cAIre must not invent a reference range.

If the source contains a reference range, the reported value can be compared with that range. If it does not, the system displays "Reference range not provided" rather than guessing.

## Provenance
Information is distinguished as:
- Patient-provided
- Extracted from a medical report
- AI-generated

## Workflow
```text
Landing -> Registration -> Patient Intake -> Dashboard
                                      |
                              Report Upload
                                      |
                              OCR / AI Extraction
                                      |
                         Structured Clinical Data
                              /      |       \
                    Reference   Provenance   Summary
                      check
```

## Testing
Run:
```bash
pip install -r requirements.txt
python testing.py
pytest -q
```

Tests cover reference-range handling, supported files, required frontend pages, intake fields, provenance terminology and safety messaging.

## Project Structure
```text
cAIre/
├── backend/
│   └── api/
│       └── index.py
├── frontend/
│   ├── index.html
│   ├── register.html
│   ├── intake.html
│   ├── dashboard.html
│   ├── upload-report.html
│   ├── report-result.html
│   ├── patient-record.html
│   └── history.html
├── tests/
│   ├── test_reference_range.py
│   ├── test_file_validation.py
│   └── test_frontend.py
├── testing.py
├── requirements.txt
├── .env.example
├── .gitignore
├── vercel.json
└── README.md
```

## Security
Keep API keys and database credentials in environment variables. Never commit `.env`. Validate uploaded files and require authentication/authorization before exposing real patient records.

## Accessibility
Use semantic HTML, explicit labels, keyboard navigation, visible focus states, responsive layouts and accessible status/error messages.

## Responsible AI
cAIre is for organizing and understanding available information. It is not a diagnostic or treatment system. AI output may contain errors and should be reviewed by an appropriate healthcare professional.

## Additional Features
The architecture can be extended with conflict detection, human verification, report comparison, persistent history, authentication, audit timelines, confidence indicators, PDF export, search/filtering and side-by-side source views.

## Assumptions
The uploaded source report is authoritative for its own reference ranges. Missing information remains missing rather than being inferred as medical fact.
