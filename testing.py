"""
cAIre smoke tests and reusable validation helpers.

Run:
    python testing.py

Full automated suite:
    pytest -q
"""

from pathlib import Path


def evaluate_reference_range(value, reference_range):
    """Classify only when the source report supplies a range."""
    if reference_range is None:
        return "Reference range not provided"
    low, high = reference_range
    if value < low:
        return "Low"
    if value > high:
        return "High"
    return "Normal"


def validate_report_file(filename):
    return Path(filename).suffix.lower() in {".pdf", ".png", ".jpg", ".jpeg"}


def run_smoke_tests():
    tests = [
        ("Below range", evaluate_reference_range(10.2, (12, 16)) == "Low"),
        ("Inside range", evaluate_reference_range(14, (12, 16)) == "Normal"),
        ("Above range", evaluate_reference_range(18, (12, 16)) == "High"),
        ("Missing range", evaluate_reference_range(10.2, None) == "Reference range not provided"),
        ("PDF accepted", validate_report_file("report.pdf")),
        ("Executable rejected", not validate_report_file("report.exe")),
    ]
    failed = 0
    for name, passed in tests:
        print(f"[{'PASS' if passed else 'FAIL'}] {name}")
        failed += not passed
    print(f"\n{len(tests)-failed}/{len(tests)} smoke tests passed.")
    return failed == 0


if __name__ == "__main__":
    raise SystemExit(0 if run_smoke_tests() else 1)
