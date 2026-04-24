import io
import os
import logging
from typing import Dict, Any, List

import joblib
import numpy as np
import pandas as pd
import requests

logger = logging.getLogger(__name__)


class VertexEvaluator:
    """
    Evaluates a pre-trained sklearn model for fairness using Vertex AI concepts.

    When a model file (.pkl) is available, this class:
    - Downloads and loads it from Firebase Storage
    - Runs predictions on a test CSV
    - Computes feature importances and group-level prediction distributions
    """

    def __init__(self):
        self.project_id = os.getenv("GOOGLE_CLOUD_PROJECT", "")
        self.location = os.getenv("VERTEX_AI_LOCATION", "us-central1")

    def _download_bytes(self, url: str) -> bytes:
        response = requests.get(url, timeout=60)
        response.raise_for_status()
        return response.content

    def evaluate_model(
        self,
        model_file_url: str,
        test_data_url: str,
        target_col: str,
        protected_attrs: List[str],
    ) -> Dict[str, Any]:
        """
        Download a .pkl model and test CSV, run predictions, and return:
        - feature_importance: dict of feature → importance score
        - group_predictions: dict of attribute → {group: prediction_rate}
        """
        # ── Load model ──────────────────────────────────────────────────────
        model_bytes = self._download_bytes(model_file_url)
        model = joblib.load(io.BytesIO(model_bytes))

        # ── Load test data ───────────────────────────────────────────────────
        csv_bytes = self._download_bytes(test_data_url)
        df = pd.read_csv(io.BytesIO(csv_bytes))

        if target_col not in df.columns:
            raise ValueError(f"Target column '{target_col}' not in test data.")

        y_true = df[target_col]
        X = df.drop(columns=[target_col])

        # Drop protected attributes before prediction (to avoid leakage)
        feature_cols = [c for c in X.columns if c not in protected_attrs]
        X_features = X[feature_cols]

        # Encode any remaining string columns with ordinal encoding
        for col in X_features.select_dtypes(include="object").columns:
            X_features = X_features.copy()
            X_features[col] = pd.Categorical(X_features[col]).codes

        y_pred = model.predict(X_features)

        # ── Feature importance ───────────────────────────────────────────────
        feature_importance: Dict[str, float] = {}
        if hasattr(model, "feature_importances_"):
            importances = model.feature_importances_
            feature_importance = {
                col: round(float(imp), 4)
                for col, imp in sorted(
                    zip(feature_cols, importances), key=lambda x: -x[1]
                )
            }
        elif hasattr(model, "coef_"):
            coefs = np.abs(model.coef_).flatten()
            feature_importance = {
                col: round(float(c), 4)
                for col, c in sorted(
                    zip(feature_cols, coefs), key=lambda x: -x[1]
                )
            }

        # ── Group prediction distributions ──────────────────────────────────
        group_predictions: Dict[str, Any] = {}
        for attr in protected_attrs:
            if attr not in df.columns:
                continue
            groups: Dict[str, float] = {}
            for grp, idx in df.groupby(attr).groups.items():
                preds_for_group = y_pred[idx]
                # Positive prediction rate
                if hasattr(preds_for_group, "mean"):
                    rate = float(
                        np.mean(preds_for_group == 1)
                        if preds_for_group.dtype in [int, float, np.int64, np.float64]
                        else np.mean(preds_for_group.astype(str) == "1")
                    )
                else:
                    rate = 0.0
                groups[str(grp)] = round(rate, 4)
            group_predictions[attr] = groups

        return {
            "feature_importance": feature_importance,
            "group_predictions": group_predictions,
            "n_samples": len(df),
            "model_type": type(model).__name__,
        }
