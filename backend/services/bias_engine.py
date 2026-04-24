import io
import logging
import re
import requests
import numpy as np
import pandas as pd
from typing import Any, Dict, List, Optional

from fairlearn.metrics import (
    demographic_parity_ratio,
    demographic_parity_difference,
    equalized_odds_difference,
    selection_rate,
    MetricFrame,
)

logger = logging.getLogger(__name__)

# Reject column names containing SQL keywords or script-injection characters.
_INJECTION_RE = re.compile(
    r"[;'\"<>{}\\]|--|\bDROP\b|\bSELECT\b|\bINSERT\b|\bUPDATE\b|\bDELETE\b|<script",
    re.IGNORECASE,
)

# Heuristics for column-name suggestions in dataset profiles.
_TARGET_KEYWORDS = ["hired", "selected", "outcome", "decision", "label", "result", "approved"]
_PROTECTED_KEYWORDS = ["gender", "sex", "race", "ethnicity", "age", "disability", "religion", "nationality", "marital"]


class BiasEngine:
    """Core bias detection engine using Fairlearn metrics."""

    # ── Column validation ────────────────────────────────────────────────────

    @staticmethod
    def validate_dataset(
        df: pd.DataFrame,
        target_col: str,
        protected_attrs: List[str],
    ) -> List[str]:
        """Return a list of warnings about the dataset.

        Raises ValueError for fatal problems (empty, limits exceeded,
        injection-looking column names, missing target).
        """
        issues: List[str] = []

        if df.empty:
            raise ValueError("Dataset is empty (0 rows).")
        if len(df) > 1_000_000:
            raise ValueError(
                f"Dataset has {len(df):,} rows which exceeds the 1,000,000-row limit. "
                "Split the file into smaller batches."
            )
        if len(df.columns) > 500:
            raise ValueError(
                f"Dataset has {len(df.columns)} columns which exceeds the 500-column limit."
            )

        for col in df.columns:
            if _INJECTION_RE.search(str(col)):
                raise ValueError(
                    f"Column name contains invalid characters or reserved keywords: '{col}'. "
                    "Please rename the column before uploading."
                )

        if len(df) < 10:
            issues.append(f"Very small dataset ({len(df)} rows) — results may be unreliable.")
        if target_col not in df.columns:
            raise ValueError(
                f"Target column '{target_col}' not found. "
                f"Available columns: {list(df.columns)}"
            )

        missing_attrs = [a for a in protected_attrs if a not in df.columns]
        if missing_attrs:
            issues.append(
                f"Protected attribute(s) not found and will be skipped: {missing_attrs}"
            )

        unique_targets = df[target_col].dropna().unique()
        if len(unique_targets) < 2:
            issues.append(
                f"Target column '{target_col}' has only {len(unique_targets)} "
                f"unique value(s): {list(unique_targets)[:5]}. "
                "Bias metrics require at least two outcome classes."
            )
        return issues

    # ── CSV loading ──────────────────────────────────────────────────────────

    def load_csv(self, url: str) -> pd.DataFrame:
        logger.info("Downloading CSV from %s", url[:120])
        response = requests.get(url, timeout=60)
        response.raise_for_status()
        df = pd.read_csv(io.StringIO(response.text))
        logger.info("Loaded CSV: %d rows × %d columns", len(df), len(df.columns))
        return df

    def load_csv_from_bytes(self, content: bytes) -> pd.DataFrame:
        df = pd.read_csv(io.BytesIO(content))
        logger.info("Loaded CSV from bytes: %d rows × %d columns", len(df), len(df.columns))
        return df

    # ── Label helpers ─────────────────────────────────────────────────────────

    def detect_positive_label(self, df: pd.DataFrame, target_col: str) -> Optional[str]:
        """Return the majority class in target_col as a string, or None."""
        if target_col not in df.columns:
            return None
        counts = df[target_col].astype(str).str.strip().value_counts()
        if counts.empty:
            return None
        return str(counts.index[0])

    # ── Numeric bucketing ────────────────────────────────────────────────────

    @staticmethod
    def _bucket_if_numeric(series: pd.Series) -> pd.Series:
        """If series is numeric, bucket into quartile labels; otherwise cast to str."""
        if pd.api.types.is_numeric_dtype(series):
            try:
                return pd.qcut(
                    series, q=4, labels=["Q1", "Q2", "Q3", "Q4"], duplicates="drop"
                ).astype(str).str.strip()
            except Exception:
                pass
        return series.astype(str).str.strip()

    # ── Per-attribute metric computation ─────────────────────────────────────

    def _compute_attr_metrics(
        self, y_true: pd.Series, sensitive: pd.Series, attr: str
    ) -> Dict[str, Any]:
        """Compute all three fairness metrics for one protected attribute."""
        attr_metrics: Dict[str, Any] = {}

        # Disparate Impact Ratio
        try:
            dir_value = demographic_parity_ratio(
                y_true=y_true, y_pred=y_true, sensitive_features=sensitive
            )
            v = float(dir_value) if not np.isnan(dir_value) else 0.0
            attr_metrics["disparate_impact"] = {
                "value": v,
                "threshold": 0.8,
                "passed": v >= 0.8,
                "description": (
                    "Disparate Impact Ratio (4/5ths rule): ratio of the lowest group "
                    "selection rate to the highest. Values below 0.8 indicate potential "
                    "adverse impact."
                ),
                "degenerate": False,
            }
        except Exception as exc:
            logger.error("Disparate impact failed for '%s': %s", attr, exc)
            attr_metrics["disparate_impact"] = {
                "value": 0.0, "threshold": 0.8, "passed": False,
                "description": f"Could not compute: {exc}", "degenerate": False,
            }

        # Demographic Parity Difference
        try:
            dpd_value = demographic_parity_difference(
                y_true=y_true, y_pred=y_true, sensitive_features=sensitive
            )
            v = float(dpd_value) if not np.isnan(dpd_value) else 0.0
            attr_metrics["demographic_parity_diff"] = {
                "value": v,
                "threshold": 0.1,
                "passed": abs(v) <= 0.1,
                "description": (
                    "Demographic Parity Difference: difference in selection rates between "
                    "the most and least favoured groups. Values above ±0.1 suggest "
                    "meaningful disparity."
                ),
                "degenerate": False,
            }
        except Exception as exc:
            logger.error("Demographic parity diff failed for '%s': %s", attr, exc)
            attr_metrics["demographic_parity_diff"] = {
                "value": 0.0, "threshold": 0.1, "passed": False,
                "description": f"Could not compute: {exc}", "degenerate": False,
            }

        # Equalized Odds Difference
        try:
            eod_value = equalized_odds_difference(
                y_true=y_true, y_pred=y_true, sensitive_features=sensitive
            )
            is_degenerate = eod_value == 0.0
            v = float(eod_value) if not np.isnan(eod_value) else 0.0
            attr_metrics["equalized_odds_diff"] = {
                "value": v,
                "threshold": 0.1,
                "passed": True if is_degenerate else abs(v) <= 0.1,
                "description": (
                    "Equalized Odds Difference: not applicable when analysing a dataset "
                    "without a separate model's predictions."
                    if is_degenerate else
                    "Equalized Odds Difference: maximum difference in true-positive and "
                    "false-positive rates across groups. Values above ±0.1 indicate the "
                    "model treats groups unequally."
                ),
                "degenerate": is_degenerate,
            }
        except Exception as exc:
            logger.error("Equalized odds diff failed for '%s': %s", attr, exc)
            attr_metrics["equalized_odds_diff"] = {
                "value": 0.0, "threshold": 0.1, "passed": False,
                "description": f"Could not compute: {exc}", "degenerate": False,
            }

        # Per-group selection rates
        mf = MetricFrame(
            metrics=selection_rate,
            y_true=y_true,
            y_pred=y_true,
            sensitive_features=sensitive,
        )
        attr_metrics["selection_rates"] = {
            str(k): round(float(v), 4) for k, v in mf.by_group.items()
        }
        attr_metrics["overall_selection_rate"] = round(float(mf.overall), 4)
        return attr_metrics

    # ── Main metric computation ──────────────────────────────────────────────

    def compute_metrics(
        self,
        df: pd.DataFrame,
        target_col: str,
        protected_attrs: List[str],
        positive_label: str,
        intersectional: bool = False,
    ) -> Dict[str, Any]:
        """Compute fairness metrics for each protected attribute.

        Supports:
        - Binary and multi-class targets (one-vs-rest worst case for multi-class)
        - Numeric protected attributes (auto-bucketed into quartiles)
        - Intersectional bias (combined attribute column when intersectional=True)
        """
        results: Dict[str, Any] = {}

        # Build working copy with bucketed numeric attrs
        df_work = df.copy()
        for attr in protected_attrs:
            if attr in df_work.columns:
                df_work[attr] = self._bucket_if_numeric(df_work[attr])

        # Add intersectional column
        effective_attrs = list(protected_attrs)
        if intersectional and len(protected_attrs) >= 2:
            present = [a for a in protected_attrs if a in df_work.columns]
            if len(present) >= 2:
                inter_col = " × ".join(present)
                combined = df_work[present[0]].astype(str).str.strip()
                for attr in present[1:]:
                    combined = combined + " × " + df_work[attr].astype(str).str.strip()
                df_work[inter_col] = combined
                effective_attrs.append(inter_col)

        # Detect multi-class target
        if target_col not in df_work.columns:
            for attr in effective_attrs:
                results[attr] = {"error": f"Target column '{target_col}' not found."}
            return results

        unique_targets = (
            df_work[target_col].astype(str).str.strip().str.lower().unique()
        )
        is_multiclass = len(unique_targets) > 2

        if is_multiclass:
            logger.info(
                "Multi-class target detected (%d classes). Using one-vs-rest worst-case.",
                len(unique_targets),
            )
            return self._compute_multiclass_worst_case(
                df_work, target_col, effective_attrs, unique_targets, positive_label
            )

        # Binary case
        pos = str(positive_label).strip().lower()
        y_true = df_work[target_col].astype(str).str.strip().str.lower().map(
            lambda v: 1 if v == pos else 0
        )

        for attr in effective_attrs:
            if attr not in df_work.columns:
                results[attr] = {"error": f"Column '{attr}' not found in dataset"}
                logger.warning("Protected attribute '%s' not found — skipping.", attr)
                continue

            sensitive = df_work[attr].astype(str).str.strip()
            n_groups = sensitive.nunique()
            logger.info("Computing metrics for '%s' (%d groups)", attr, n_groups)
            results[attr] = self._compute_attr_metrics(y_true, sensitive, attr)

        return results

    def _compute_multiclass_worst_case(
        self,
        df: pd.DataFrame,
        target_col: str,
        protected_attrs: List[str],
        unique_targets: np.ndarray,
        positive_label: str,
    ) -> Dict[str, Any]:
        """One-vs-rest across all classes; return worst-case (lowest DI) per attr."""
        pos = str(positive_label).strip().lower()
        # Ensure the user-specified positive_label is tried first
        classes = [pos] + [c for c in unique_targets if c != pos]

        # per-attr: {attr: (best_metrics, worst_di, pivot_class)}
        worst_by_attr: Dict[str, tuple] = {}

        for cls in classes:
            y_true = df[target_col].astype(str).str.strip().str.lower().map(
                lambda v, c=cls: 1 if v == c else 0
            )
            for attr in protected_attrs:
                if attr not in df.columns:
                    continue
                sensitive = df[attr].astype(str).str.strip()
                try:
                    attr_metrics = self._compute_attr_metrics(y_true, sensitive, attr)
                    di = attr_metrics.get("disparate_impact", {}).get("value", 1.0)
                    if attr not in worst_by_attr or di < worst_by_attr[attr][1]:
                        worst_by_attr[attr] = (attr_metrics, di, cls)
                except Exception as exc:
                    logger.warning("Multi-class metric failed for '%s' cls '%s': %s", attr, cls, exc)

        results: Dict[str, Any] = {}
        for attr in protected_attrs:
            if attr in worst_by_attr:
                m, _, pivot = worst_by_attr[attr]
                m["multiclass_pivot_class"] = pivot
                results[attr] = m
            else:
                results[attr] = {"error": f"Column '{attr}' not found in dataset"}
        return results

    # ── Fairness score ────────────────────────────────────────────────────────

    def compute_fairness_score(self, metrics: Dict[str, Any]) -> float:
        """100 × (non-degenerate checks passed / total non-degenerate checks), per attr averaged."""
        metric_keys = ["disparate_impact", "demographic_parity_diff", "equalized_odds_diff"]
        total = 0
        passed = 0

        for attr_data in metrics.values():
            if "error" in attr_data:
                continue
            for key in metric_keys:
                if key in attr_data:
                    if attr_data[key].get("degenerate", False):
                        continue
                    total += 1
                    if attr_data[key].get("passed", False):
                        passed += 1

        if total == 0:
            return 100.0
        return round(100.0 * passed / total, 2)

    # ── Chart data ────────────────────────────────────────────────────────────

    def get_chart_data(
        self,
        df: pd.DataFrame,
        target_col: str,
        protected_attrs: List[str],
        positive_label: str,
    ) -> Dict[str, Any]:
        pos = str(positive_label).strip().lower()
        y_true = df[target_col].astype(str).str.strip().str.lower().map(
            lambda v: 1 if v == pos else 0
        )

        chart: Dict[str, Any] = {}
        for attr in protected_attrs:
            if attr not in df.columns:
                continue
            sensitive = self._bucket_if_numeric(df[attr])
            mf = MetricFrame(
                metrics=selection_rate,
                y_true=y_true,
                y_pred=y_true,
                sensitive_features=sensitive,
            )
            chart[attr] = {
                "groups": list(mf.by_group.index.astype(str)),
                "selection_rates": [round(float(v), 4) for v in mf.by_group.values],
            }
        return chart

    # ── Dataset summary (for Gemini prompt) ──────────────────────────────────

    def get_dataset_summary(
        self, df: pd.DataFrame, protected_attrs: List[str]
    ) -> Dict[str, Any]:
        summary: Dict[str, Any] = {
            "rows": len(df),
            "columns": list(df.columns),
            "group_distributions": {},
        }
        for attr in protected_attrs:
            if attr in df.columns:
                dist = df[attr].value_counts(normalize=True).round(4).to_dict()
                summary["group_distributions"][attr] = {
                    str(k): float(v) for k, v in dist.items()
                }
        return summary

    # ── Dataset profile (for API response, Area 2) ────────────────────────────

    def build_dataset_profile(
        self,
        df: pd.DataFrame,
        target_col: str,
        protected_attrs: List[str],
    ) -> Dict[str, Any]:
        """Return dtypes, missing %, class imbalance, and heuristic column suggestions."""
        column_dtypes = {col: str(dtype) for col, dtype in df.dtypes.items()}
        missing_pct = {
            col: round(float(df[col].isna().mean() * 100), 2) for col in df.columns
        }

        class_distribution: Dict[str, float] = {}
        class_imbalance_ratio = 1.0
        if target_col in df.columns:
            vc = df[target_col].astype(str).value_counts(normalize=True)
            class_distribution = {k: round(float(v), 4) for k, v in vc.items()}
            if len(vc) >= 2:
                class_imbalance_ratio = round(float(vc.iloc[0] / vc.iloc[-1]), 2)

        detected_target = None
        for kw in _TARGET_KEYWORDS:
            matches = [c for c in df.columns if kw in c.lower()]
            if matches:
                detected_target = matches[0]
                break

        detected_protected = [
            c for c in df.columns
            if any(kw in c.lower() for kw in _PROTECTED_KEYWORDS)
        ]
        detected_positive_label = (
            self.detect_positive_label(df, target_col)
            if target_col in df.columns else None
        )

        return {
            "rows": len(df),
            "columns": len(df.columns),
            "column_dtypes": column_dtypes,
            "missing_pct": missing_pct,
            "class_distribution": class_distribution,
            "class_imbalance_ratio": class_imbalance_ratio,
            "detected_target": detected_target,
            "detected_protected_attrs": detected_protected,
            "detected_positive_label": detected_positive_label,
        }
