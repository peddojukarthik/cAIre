from testing import evaluate_reference_range

def test_below_reference_range():
    assert evaluate_reference_range(10.2, (12, 16)) == "Low"

def test_inside_reference_range():
    assert evaluate_reference_range(14, (12, 16)) == "Normal"

def test_above_reference_range():
    assert evaluate_reference_range(18, (12, 16)) == "High"

def test_missing_reference_range():
    assert evaluate_reference_range(10.2, None) == "Reference range not provided"
