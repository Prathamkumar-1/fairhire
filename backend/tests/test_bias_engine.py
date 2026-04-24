"""
Unit tests for BiasEngine.

Tests run against pure computation with synthetic DataFrames — no DB or network.
Run from repo root: pytest  (pyproject.toml sets pythonpath=["backend"])
"""

import numpy as np
import pandas as pd
import pytest

from services.bias_engine import BiasEngine

engine = BiasEngine()


# ── Fixtures ──────────────────────────────────────────────────────────────────

def _make_binary_df(n: int = 200, bias: bool = True, seed: int = 42) -> pd.DataFrame:
    """Synthetic hiring DataFrame with optional gender bias."""
    rng = np.random.default_rng(seed)
    gender = rng.choice(["Male", "Female"], size=n)
    if bias:
        hired = np.where(
            gender == "Male",
            rng.binomial(1, 0.75, n),
            rng.binomial(1, 0.25, n),
        )
    else:
        hired = rng.binomial(1, 0.50, n)
    return pd.DataFrame({"gender": gender, "hired": hired})


def _make_multiclass_df(n: int = 300) -> pd.DataFrame:
    rng = np.random.default_rng(0)
    gender = rng.choice(["Male", "Female", "Non-binary"], size=n)
    outcome = rng.choice(["hired", "waitlisted", "rejected"], size=n, p=[0.3, 0.3, 0.4])
    return pd.DataFrame({"gender": gender, "outcome": outcome})


def _make_numeric_attr_df(n: int = 200) -> pd.DataFrame:
    rng = np.random.default_rng(7)
    age = rng.integers(22, 65, size=n)
    hired = (age < 40).astype(int)  # age bias baked in
    return pd.DataFrame({"age": age, "hired": hired})


# ── validate_dataset ──────────────────────────────────────────────────────────

class TestValidateDataset:
    def test_empty_dataframe_raises(self):
        with pytest.raises(ValueError, match="empty"):
            engine.validate_dataset(pd.DataFrame(), "hired", ["gender"])

    def test_missing_target_raises(self):
        df = _make_binary_df()
        with pytest.raises(ValueError, match="Target column"):
            engine.validate_dataset(df, "nonexistent", ["gender"])

    def test_small_dataset_warns(self):
        df = _make_binary_df(5)
        warnings = engine.validate_dataset(df, "hired", ["gender"])
        assert any("small" in w.lower() for w in warnings)

    def test_missing_protected_attr_warns(self):
        df = _make_binary_df()
        warnings = engine.validate_dataset(df, "hired", ["gender", "race"])
        assert any("race" in w for w in warnings)

    def test_too_many_columns_raises(self):
        many_cols = {f"col_{i}": [0] * 5 for i in range(501)}
        many_cols["target"] = [1] * 5
        df = pd.DataFrame(many_cols)
        with pytest.raises(ValueError, match="column"):
            engine.validate_dataset(df, "target", [])

    def test_too_many_rows_raises(self):
        # Use a column of 1M+1 zeros rather than constructing the full DataFrame in memory
        df = pd.DataFrame({"hired": np.zeros(1_000_001, dtype=int), "g": ["M"] * 1_000_001})
        with pytest.raises(ValueError, match="row"):
            engine.validate_dataset(df, "hired", ["g"])

    def test_sql_injection_column_name_raises(self):
        df = pd.DataFrame({"hired": [1], "gender; DROP TABLE users--": ["M"]})
        with pytest.raises(ValueError, match="invalid"):
            engine.validate_dataset(df, "hired", ["gender; DROP TABLE users--"])

    def test_script_injection_column_name_raises(self):
        df = pd.DataFrame({"hired": [1], "<script>alert(1)</script>": ["M"]})
        with pytest.raises(ValueError, match="invalid"):
            engine.validate_dataset(df, "hired", ["<script>alert(1)</script>"])

    def test_select_keyword_in_col_raises(self):
        df = pd.DataFrame({"hired": [1], "SELECT * FROM users": ["M"]})
        with pytest.raises(ValueError, match="invalid"):
            engine.validate_dataset(df, "hired", ["SELECT * FROM users"])

    def test_valid_large_dataset_no_error(self):
        df = _make_binary_df(500)
        warnings = engine.validate_dataset(df, "hired", ["gender"])
        assert warnings == []


# ── detect_positive_label ─────────────────────────────────────────────────────

class TestDetectPositiveLabel:
    def test_detects_majority_class(self):
        df = pd.DataFrame({"hired": ["1"] * 70 + ["0"] * 30})
        label = engine.detect_positive_label(df, "hired")
        assert label == "1"

    def test_returns_none_for_missing_column(self):
        df = _make_binary_df(10)
        assert engine.detect_positive_label(df, "nonexistent") is None

    def test_returns_something_for_balanced(self):
        df = pd.DataFrame({"hired": ["yes"] * 50 + ["no"] * 50})
        label = engine.detect_positive_label(df, "hired")
        assert label in ("yes", "no")


# ── compute_metrics (binary) ──────────────────────────────────────────────────

class TestComputeMetricsBinary:
    def test_biased_dataset_fails_disparate_impact(self):
        df = _make_binary_df(500, bias=True)
        metrics = engine.compute_metrics(df, "hired", ["gender"], "1")
        di = metrics["gender"]["disparate_impact"]
        assert di["value"] < 0.8
        assert not di["passed"]

    def test_fair_dataset_passes_disparate_impact(self):
        df = _make_binary_df(500, bias=False)
        metrics = engine.compute_metrics(df, "hired", ["gender"], "1")
        di = metrics["gender"]["disparate_impact"]
        assert di["value"] >= 0.8
        assert di["passed"]

    def test_equalized_odds_is_degenerate(self):
        df = _make_binary_df(100)
        metrics = engine.compute_metrics(df, "hired", ["gender"], "1")
        eod = metrics["gender"]["equalized_odds_diff"]
        assert eod["degenerate"] is True
        assert eod["value"] == 0.0

    def test_missing_protected_attr_returns_error(self):
        df = _make_binary_df(100)
        metrics = engine.compute_metrics(df, "hired", ["nonexistent_col"], "1")
        assert "error" in metrics["nonexistent_col"]

    def test_positive_label_case_insensitive(self):
        df = pd.DataFrame({
            "gender": ["M", "M", "F", "F"] * 25,
            "hired": ["YES", "Yes", "no", "NO"] * 25,
        })
        metrics = engine.compute_metrics(df, "hired", ["gender"], "yes")
        assert "gender" in metrics
        assert "error" not in metrics["gender"]

    def test_selection_rates_present(self):
        df = _make_binary_df(100)
        metrics = engine.compute_metrics(df, "hired", ["gender"], "1")
        rates = metrics["gender"]["selection_rates"]
        assert len(rates) > 0
        assert all(0.0 <= v <= 1.0 for v in rates.values())

    def test_all_metric_keys_present(self):
        df = _make_binary_df(100)
        metrics = engine.compute_metrics(df, "hired", ["gender"], "1")
        for key in ("disparate_impact", "demographic_parity_diff", "equalized_odds_diff"):
            assert key in metrics["gender"]


# ── compute_metrics (numeric protected attribute) ─────────────────────────────

class TestNumericProtectedAttribute:
    def test_numeric_attr_bucketed_to_quartiles(self):
        df = _make_numeric_attr_df(200)
        metrics = engine.compute_metrics(df, "hired", ["age"], "1")
        assert "age" in metrics
        assert "error" not in metrics["age"]
        rates = metrics["age"]["selection_rates"]
        # Quartile labels Q1..Q4 (or a subset if duplicates)
        assert all(k.startswith("Q") for k in rates)

    def test_numeric_attr_chart_data_bucketed(self):
        df = _make_numeric_attr_df(200)
        chart = engine.get_chart_data(df, "hired", ["age"], "1")
        assert "age" in chart
        assert all(g.startswith("Q") for g in chart["age"]["groups"])


# ── compute_metrics (multi-class) ─────────────────────────────────────────────

class TestMulticlassTarget:
    def test_multiclass_returns_metrics_per_attr(self):
        df = _make_multiclass_df(300)
        metrics = engine.compute_metrics(df, "outcome", ["gender"], "hired")
        assert "gender" in metrics
        assert "error" not in metrics["gender"]

    def test_multiclass_records_pivot_class(self):
        df = _make_multiclass_df(300)
        metrics = engine.compute_metrics(df, "outcome", ["gender"], "hired")
        # Worst-case pivot class should be set
        assert "multiclass_pivot_class" in metrics["gender"]

    def test_multiclass_pivot_is_valid_class(self):
        df = _make_multiclass_df(300)
        metrics = engine.compute_metrics(df, "outcome", ["gender"], "hired")
        pivot = metrics["gender"]["multiclass_pivot_class"]
        valid_classes = df["outcome"].astype(str).str.strip().str.lower().unique()
        assert pivot in valid_classes


# ── compute_metrics (intersectional) ─────────────────────────────────────────

class TestIntersectionalBias:
    def test_intersectional_column_added(self):
        df = pd.DataFrame({
            "gender": ["Male", "Female"] * 100,
            "race": ["A", "B"] * 100,
            "hired": [1, 0] * 100,
        })
        metrics = engine.compute_metrics(df, "hired", ["gender", "race"], "1", intersectional=True)
        inter_key = "gender × race"
        assert inter_key in metrics

    def test_intersectional_false_does_not_add_column(self):
        df = pd.DataFrame({
            "gender": ["Male", "Female"] * 100,
            "race": ["A", "B"] * 100,
            "hired": [1, 0] * 100,
        })
        metrics = engine.compute_metrics(df, "hired", ["gender", "race"], "1", intersectional=False)
        assert "gender × race" not in metrics


# ── compute_fairness_score ────────────────────────────────────────────────────

class TestFairnessScore:
    def test_all_passed_gives_100(self):
        metrics = {
            "gender": {
                "disparate_impact": {"passed": True, "degenerate": False},
                "demographic_parity_diff": {"passed": True, "degenerate": False},
                "equalized_odds_diff": {"passed": True, "degenerate": True},
            }
        }
        assert engine.compute_fairness_score(metrics) == 100.0

    def test_all_failed_gives_0(self):
        metrics = {
            "gender": {
                "disparate_impact": {"passed": False, "degenerate": False},
                "demographic_parity_diff": {"passed": False, "degenerate": False},
                "equalized_odds_diff": {"passed": False, "degenerate": False},
            }
        }
        assert engine.compute_fairness_score(metrics) == 0.0

    def test_degenerate_excluded_from_denominator(self):
        metrics = {
            "gender": {
                "disparate_impact": {"passed": True, "degenerate": False},
                "demographic_parity_diff": {"passed": False, "degenerate": False},
                "equalized_odds_diff": {"passed": True, "degenerate": True},  # excluded
            }
        }
        # 1 passed / 2 non-degenerate = 50.0
        assert engine.compute_fairness_score(metrics) == 50.0

    def test_empty_metrics_gives_100(self):
        assert engine.compute_fairness_score({}) == 100.0

    def test_all_error_attrs_gives_100(self):
        metrics = {"gender": {"error": "Column not found"}}
        assert engine.compute_fairness_score(metrics) == 100.0

    def test_score_in_range(self):
        df = _make_binary_df(500, bias=True)
        metrics = engine.compute_metrics(df, "hired", ["gender"], "1")
        score = engine.compute_fairness_score(metrics)
        assert 0.0 <= score <= 100.0

    def test_multiple_attrs_averaged(self):
        metrics = {
            "gender": {
                "disparate_impact": {"passed": True, "degenerate": False},
                "demographic_parity_diff": {"passed": True, "degenerate": False},
                "equalized_odds_diff": {"passed": True, "degenerate": True},
            },
            "race": {
                "disparate_impact": {"passed": False, "degenerate": False},
                "demographic_parity_diff": {"passed": False, "degenerate": False},
                "equalized_odds_diff": {"passed": False, "degenerate": False},
            },
        }
        # gender: 2/2=100, race: 0/3=0 → total 2/5=40.0
        assert engine.compute_fairness_score(metrics) == 40.0


# ── build_dataset_profile ─────────────────────────────────────────────────────

class TestBuildDatasetProfile:
    def test_profile_contains_required_keys(self):
        df = _make_binary_df(100)
        profile = engine.build_dataset_profile(df, "hired", ["gender"])
        for key in ("rows", "columns", "column_dtypes", "missing_pct", "class_distribution"):
            assert key in profile

    def test_detects_target_column_by_name(self):
        df = pd.DataFrame({"candidate_id": range(10), "hired": [1] * 10, "gender": ["M"] * 10})
        profile = engine.build_dataset_profile(df, "hired", ["gender"])
        assert profile["detected_target"] == "hired"

    def test_detects_protected_attrs_by_name(self):
        df = pd.DataFrame({"hired": [1] * 10, "gender": ["M"] * 10, "age": [30] * 10})
        profile = engine.build_dataset_profile(df, "hired", ["gender", "age"])
        assert "gender" in profile["detected_protected_attrs"]
        assert "age" in profile["detected_protected_attrs"]

    def test_missing_pct_correct(self):
        df = pd.DataFrame({"hired": [1, None, 1, None, 1], "gender": ["M"] * 5})
        profile = engine.build_dataset_profile(df, "hired", ["gender"])
        assert profile["missing_pct"]["hired"] == 40.0

    def test_class_imbalance_ratio_computed(self):
        df = pd.DataFrame({
            "hired": ["1"] * 80 + ["0"] * 20,
            "gender": ["M"] * 100,
        })
        profile = engine.build_dataset_profile(df, "hired", ["gender"])
        assert profile["class_imbalance_ratio"] == 4.0  # 80/20
