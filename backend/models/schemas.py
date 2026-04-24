from pydantic import BaseModel, Field, field_validator
from typing import Any, Dict, List, Optional


class AnalysisRequest(BaseModel):
    dataset_url: str = Field(
        ...,
        description="Firebase Storage download URL of the CSV dataset",
        json_schema_extra={"example": "https://storage.googleapis.com/bucket/hiring.csv"},
    )
    target_column: str = Field(
        ..., description="Name of the outcome column (e.g. 'hired')",
        json_schema_extra={"example": "hired"},
    )
    protected_attributes: List[str] = Field(
        ...,
        description="List of protected attribute column names to check for bias",
        min_length=1,
        json_schema_extra={"example": ["gender", "age_group"]},
    )
    positive_label: str = Field(
        ...,
        description="Value in the target column that means a positive outcome",
        json_schema_extra={"example": "1"},
    )
    user_id: str = Field(..., description="Firebase Auth UID of the requesting user", min_length=1)
    intersectional: bool = Field(
        False,
        description="When True, also compute metrics on the intersection of all protected attributes.",
    )

    @field_validator("target_column", "positive_label")
    @classmethod
    def strip_whitespace(cls, v: str) -> str:
        return v.strip()


class BiasMetric(BaseModel):
    name: str
    value: float
    threshold: float
    passed: bool
    description: str


class DatasetProfile(BaseModel):
    """Summary of the uploaded CSV for display in the report."""
    rows: int
    columns: int
    column_dtypes: Dict[str, str]
    missing_pct: Dict[str, float]
    class_distribution: Dict[str, float]
    class_imbalance_ratio: float
    detected_target: Optional[str] = None
    detected_protected_attrs: List[str] = []
    detected_positive_label: Optional[str] = None


class AnalysisResult(BaseModel):
    audit_id: str
    timestamp: str
    fairness_score: float = Field(ge=0, le=100)
    metrics: List[BiasMetric]
    gemini_explanation: str
    gemini_recommendations: List[str]
    at_risk_features: List[str]
    chart_data: Dict[str, Any]
    verdict: Optional[str] = None
    verdict_reason: Optional[str] = None
    urgent_issues: Optional[List[str]] = None
    dataset_filename: Optional[str] = None
    dataset_profile: Optional[DatasetProfile] = None
    intersectional_metrics: Optional[List[BiasMetric]] = None


class AnalysisSummary(BaseModel):
    audit_id: str
    timestamp: str
    fairness_score: float
    verdict: Optional[str] = None
    dataset_filename: Optional[str] = None
    at_risk_features: List[str] = []


class UploadResponse(BaseModel):
    download_url: str
    filename: str
    user_id: str


class JobStatus(BaseModel):
    audit_id: str
    status: str  # pending | running | completed | failed
    result: Optional[AnalysisResult] = None
    error: Optional[str] = None


class PreviewResponse(BaseModel):
    """Returned by POST /analyze/preview — used to auto-populate the UI."""
    columns: List[str]
    dtypes: Dict[str, str]
    sample_values: Dict[str, List[str]]
    suggested_target: Optional[str] = None
    suggested_protected_attrs: List[str] = []
    detected_positive_label: Optional[str] = None
    row_count: int
    column_count: int


class TrendPoint(BaseModel):
    """One week's aggregated fairness stats for the trend chart."""
    week: str  # ISO week label e.g. "2025-W42"
    avg_score: float
    pass_count: int
    caution_count: int
    fail_count: int


class BatchSummary(BaseModel):
    """Per-file result from POST /analyze/batch."""
    filename: str
    audit_id: str
    fairness_score: float
    verdict: Optional[str] = None
    at_risk_features: List[str] = []
    error: Optional[str] = None
