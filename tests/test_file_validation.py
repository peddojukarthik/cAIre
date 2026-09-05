from testing import validate_report_file

def test_supported_pdf():
    assert validate_report_file("blood_report.pdf")

def test_supported_image():
    assert validate_report_file("report.JPG")

def test_unsupported_file():
    assert not validate_report_file("report.exe")
