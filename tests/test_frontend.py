from pathlib import Path

FRONTEND = Path(__file__).parents[1] / "frontend"

REQUIRED_PAGES = [
    "index.html", "register.html", "intake.html", "dashboard.html",
    "upload-report.html", "report-result.html", "patient-record.html", "history.html"
]

def test_required_frontend_pages_exist():
    for page in REQUIRED_PAGES:
        assert (FRONTEND / page).exists(), f"Missing frontend/{page}"

def test_intake_fields_exist():
    html = (FRONTEND / "intake.html").read_text(encoding="utf-8").lower()
    for field in ["patient name", "age", "sex", "symptoms", "existing conditions",
                  "allergies", "current medications"]:
        assert field in html

def test_report_fields_exist():
    html = (FRONTEND / "report-result.html").read_text(encoding="utf-8").lower()
    assert "source" in html
    assert "reference range" in html

def test_safety_message_exists():
    html = "\n".join(p.read_text(encoding="utf-8").lower() for p in FRONTEND.glob("*.html"))
    assert "diagnosis" in html
