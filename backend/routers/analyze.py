import asyncio
import io
import logging
import os
import uuid
import zipfile
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

import firebase_admin
from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from firebase_admin import auth as firebase_auth, firestore

from limiter import limiter
from models.schemas import (
    AnalysisRequest,
    AnalysisResult,
    AnalysisSummary,
    BatchSummary,
    BiasMetric,
    DatasetProfile,
    JobStatus,
    PreviewResponse,
    TrendPoint,
    UploadResponse,
)
from services.bias_engine import BiasEngine, _TARGET_KEYWORDS, _PROTECTED_KEYWORDS
from services.gemini_advisor import GeminiAdvisor

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/analyze", tags=["analyze"])

_bias_engine = BiasEngine()
_gemini = GeminiAdvisor()

MAX_FILE_SIZE = 50 * 1024 * 1024  # 50 MB
MAX_BATCH_FILES = 20


# ── Auth helper ───────────────────────────────────────────────────────────────

async def _check_auth(request: Request, user_id: str) -> None:
    """Verify Firebase ID token if REQUIRE_AUTH=true in env."""
    if os.getenv("REQUIRE_AUTH", "false").lower() != "true":
        return
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header.")
    token = auth_header.removeprefix("Bearer ").strip()
    try:
        decoded = firebase_auth.verify_id_token(token)
        if decoded["uid"] != user_id:
            raise HTTPException(
                status_code=403, detail="Token uid does not match user_id field."
            )
    except firebase_admin.auth.InvalidIdTokenError as exc:  # type: ignore[attr-defined]
        raise HTTPException(status_code=401, detail=f"Invalid ID token: {exc}")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=401, detail=f"Token verification failed: {exc}")


# ── Pipeline helpers ──────────────────────────────────────────────────────────

def _build_bias_metrics(metrics: dict) -> List[BiasMetric]:
    result: List[BiasMetric] = []
    metric_display = {
        "disparate_impact": "Disparate Impact Ratio",
        "demographic_parity_diff": "Demographic Parity Difference",
        "equalized_odds_diff": "Equalized Odds Difference",
    }
    for attr, attr_data in metrics.items():
        if "error" in attr_data:
            continue
        for key, display_name in metric_display.items():
            if key not in attr_data:
                continue
            m = attr_data[key]
            if m.get("degenerate", False):
                continue
            result.append(
                BiasMetric(
                    name=f"{display_name} ({attr})",
                    value=round(m["value"], 4),
                    threshold=m["threshold"],
                    passed=m["passed"],
                    description=m["description"],
                )
            )
    return result


def _get_at_risk_features(metrics: dict) -> List[str]:
    at_risk = []
    for attr, attr_data in metrics.items():
        if "error" in attr_data:
            continue
        failed = any(
            not attr_data.get(k, {}).get("passed", True)
            for k in ["disparate_impact", "demographic_parity_diff", "equalized_odds_diff"]
            if not attr_data.get(k, {}).get("degenerate", False)
        )
        if failed:
            at_risk.append(attr)
    return at_risk


def _run_analysis_sync(
    df,
    target_column: str,
    attrs: List[str],
    positive_label: str,
    intersectional: bool,
    dataset_filename: str,
) -> Dict[str, Any]:
    """CPU-bound analysis work — runs in a thread pool via asyncio.to_thread."""
    metrics = _bias_engine.compute_metrics(df, target_column, attrs, positive_label, intersectional)
    fairness_score = _bias_engine.compute_fairness_score(metrics)
    chart_data = _bias_engine.get_chart_data(df, target_column, attrs, positive_label)
    dataset_summary = _bias_engine.get_dataset_summary(df, attrs)
    dataset_profile_dict = _bias_engine.build_dataset_profile(df, target_column, attrs)
    gemini_result = _gemini.explain_bias(metrics, fairness_score, dataset_summary)

    # Separate intersectional metrics from normal ones
    inter_key = " × ".join(attrs) if intersectional and len(attrs) >= 2 else None
    intersectional_raw = {}
    normal_metrics = {}
    for k, v in metrics.items():
        if inter_key and k == inter_key:
            intersectional_raw = {k: v}
        else:
            normal_metrics[k] = v

    bias_metrics = _build_bias_metrics(normal_metrics)
    intersectional_metrics = _build_bias_metrics(intersectional_raw) if intersectional_raw else None
    at_risk = _get_at_risk_features(normal_metrics)

    profile = DatasetProfile(**dataset_profile_dict)

    return {
        "fairness_score": fairness_score,
        "bias_metrics": bias_metrics,
        "intersectional_metrics": intersectional_metrics,
        "at_risk": at_risk,
        "chart_data": chart_data,
        "gemini_result": gemini_result,
        "profile": profile,
    }


def _persist_audit(result: AnalysisResult, user_id: str) -> None:
    """Non-fatal Firestore write."""
    try:
        db = firestore.client()
        doc_data = result.model_dump()
        doc_data["user_id"] = user_id
        db.collection("audits").document(result.audit_id).set(doc_data)
        logger.info("Audit %s saved to Firestore.", result.audit_id)
    except Exception as exc:
        logger.warning("Firestore write failed (non-fatal): %s", exc)


def _build_result(computed: Dict[str, Any], audit_id: str, dataset_filename: str) -> AnalysisResult:
    g = computed["gemini_result"]
    return AnalysisResult(
        audit_id=audit_id,
        timestamp=datetime.now(timezone.utc).isoformat(),
        fairness_score=computed["fairness_score"],
        metrics=computed["bias_metrics"],
        intersectional_metrics=computed.get("intersectional_metrics"),
        gemini_explanation=g["explanation"],
        gemini_recommendations=g["recommendations"],
        at_risk_features=computed["at_risk"],
        chart_data=computed["chart_data"],
        verdict=g.get("verdict"),
        verdict_reason=g.get("verdict_reason"),
        urgent_issues=g.get("urgent_issues"),
        dataset_filename=dataset_filename,
        dataset_profile=computed.get("profile"),
    )


# ── POST /analyze  (URL-based) ────────────────────────────────────────────────

@router.post("", response_model=AnalysisResult)
async def run_analysis(request_body: AnalysisRequest, request: Request):
    await _check_auth(request, request_body.user_id)

    try:
        df = _bias_engine.load_csv(request_body.dataset_url)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Could not load dataset: {exc}")

    try:
        warnings = _bias_engine.validate_dataset(
            df, request_body.target_column, request_body.protected_attributes
        )
        for w in warnings:
            logger.warning("Dataset warning: %s", w)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    computed = await asyncio.to_thread(
        _run_analysis_sync,
        df,
        request_body.target_column,
        request_body.protected_attributes,
        request_body.positive_label,
        request_body.intersectional,
        request_body.dataset_url.split("/")[-1].split("?")[0],
    )
    audit_id = str(uuid.uuid4())
    result = _build_result(computed, audit_id, request_body.dataset_url.split("/")[-1].split("?")[0])
    _persist_audit(result, request_body.user_id)
    return result


# ── POST /analyze/upload  (Firebase Storage upload) ──────────────────────────

@router.post("/upload", response_model=UploadResponse)
async def upload_dataset(
    request: Request,
    file: UploadFile = File(...),
    user_id: str = Form(...),
):
    await _check_auth(request, user_id)
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Only CSV files are supported.")

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    storage_path = f"audits/{user_id}/{timestamp}/{file.filename}"
    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=413,
            detail=f"File too large ({len(content) / (1024*1024):.1f} MB). Maximum is 50 MB.",
        )

    try:
        from firebase_admin import storage
        bucket = storage.bucket()
        blob = bucket.blob(storage_path)
        blob.upload_from_string(content, content_type="text/csv")
        blob.make_public()
        download_url = blob.public_url
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Firebase Storage upload failed: {exc}")

    return UploadResponse(download_url=download_url, filename=file.filename, user_id=user_id)


# ── POST /analyze/upload-and-analyze  (demo-friendly, no Storage needed) ─────

@router.post("/upload-and-analyze", response_model=AnalysisResult)
@limiter.limit("10/minute")
async def upload_and_analyze(
    request: Request,
    file: UploadFile = File(...),
    user_id: str = Form(...),
    target_column: str = Form(...),
    protected_attributes: str = Form(...),
    positive_label: str = Form(...),
    intersectional: bool = Form(False),
):
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Only CSV files are supported.")

    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=413,
            detail=f"File too large ({len(content) / (1024*1024):.1f} MB). Maximum is 50 MB.",
        )

    try:
        df = _bias_engine.load_csv_from_bytes(content)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Could not parse CSV: {exc}")

    attrs = [a.strip() for a in protected_attributes.split(",") if a.strip()]

    try:
        warnings = _bias_engine.validate_dataset(df, target_column, attrs)
        for w in warnings:
            logger.warning("Dataset warning: %s", w)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    computed = await asyncio.to_thread(
        _run_analysis_sync, df, target_column, attrs, positive_label, intersectional, file.filename
    )
    audit_id = str(uuid.uuid4())
    result = _build_result(computed, audit_id, file.filename)
    _persist_audit(result, user_id)
    return result


# ── POST /analyze/submit  (async non-blocking submission) ────────────────────

@router.post("/submit", response_model=JobStatus)
async def submit_analysis(
    request: Request,
    file: UploadFile = File(...),
    user_id: str = Form(...),
    target_column: str = Form(...),
    protected_attributes: str = Form(...),
    positive_label: str = Form(...),
    intersectional: bool = Form(False),
):
    """Submit a large CSV for analysis without blocking. Poll /status/{audit_id}."""
    await _check_auth(request, user_id)
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Only CSV files are supported.")

    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=413, detail="File too large. Maximum is 50 MB.")

    audit_id = str(uuid.uuid4())
    filename = file.filename

    # Write initial job record to Firestore so polling works across instances
    try:
        db = firestore.client()
        db.collection("jobs").document(audit_id).set({
            "status": "pending",
            "user_id": user_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })
    except Exception as exc:
        logger.warning("Could not write job record to Firestore: %s", exc)

    attrs = [a.strip() for a in protected_attributes.split(",") if a.strip()]

    async def _background():
        try:
            db = firestore.client()
            db.collection("jobs").document(audit_id).update({"status": "running"})
        except Exception:
            pass
        try:
            df = _bias_engine.load_csv_from_bytes(content)
            _bias_engine.validate_dataset(df, target_column, attrs)
            computed = await asyncio.to_thread(
                _run_analysis_sync, df, target_column, attrs, positive_label, intersectional, filename
            )
            result = _build_result(computed, audit_id, filename)
            _persist_audit(result, user_id)
            try:
                db = firestore.client()
                db.collection("jobs").document(audit_id).update({"status": "completed"})
            except Exception:
                pass
        except Exception as exc:
            logger.error("Background job %s failed: %s", audit_id, exc)
            try:
                db = firestore.client()
                db.collection("jobs").document(audit_id).update({
                    "status": "failed", "error": str(exc)
                })
            except Exception:
                pass

    asyncio.create_task(_background())
    return JobStatus(audit_id=audit_id, status="pending")


# ── GET /analyze/status/{audit_id}  (polling endpoint) ───────────────────────

@router.get("/status/{audit_id}", response_model=JobStatus)
async def get_job_status(audit_id: str):
    """Poll the status of an async job submitted via /analyze/submit."""
    try:
        db = firestore.client()
        job_doc = db.collection("jobs").document(audit_id).get()
        if not job_doc.exists:
            # May already be completed and not tracked as a job
            audit_doc = db.collection("audits").document(audit_id).get()
            if audit_doc.exists:
                return JobStatus(audit_id=audit_id, status="completed")
            raise HTTPException(status_code=404, detail=f"Job '{audit_id}' not found.")

        data = job_doc.to_dict()
        status = data.get("status", "pending")
        error = data.get("error")

        result = None
        if status == "completed":
            try:
                audit_doc = db.collection("audits").document(audit_id).get()
                if audit_doc.exists:
                    d = audit_doc.to_dict()
                    result = AnalysisResult(
                        audit_id=d.get("audit_id", audit_id),
                        timestamp=d.get("timestamp", ""),
                        fairness_score=d.get("fairness_score", 0.0),
                        metrics=d.get("metrics", []),
                        gemini_explanation=d.get("gemini_explanation", ""),
                        gemini_recommendations=d.get("gemini_recommendations", []),
                        at_risk_features=d.get("at_risk_features", []),
                        chart_data=d.get("chart_data", {}),
                        verdict=d.get("verdict"),
                        verdict_reason=d.get("verdict_reason"),
                        urgent_issues=d.get("urgent_issues"),
                        dataset_filename=d.get("dataset_filename"),
                    )
            except Exception as exc:
                logger.warning("Could not hydrate completed result: %s", exc)

        return JobStatus(audit_id=audit_id, status=status, result=result, error=error)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Firestore error: {exc}")


# ── POST /analyze/preview  (CSV column auto-detection) ───────────────────────

@router.post("/preview", response_model=PreviewResponse)
async def preview_dataset(file: UploadFile = File(...)):
    """Parse a CSV and return column metadata + heuristic field suggestions."""
    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=413, detail="File too large. Maximum is 50 MB.")
    try:
        df = _bias_engine.load_csv_from_bytes(content)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Could not parse CSV: {exc}")

    dtypes = {col: str(dtype) for col, dtype in df.dtypes.items()}
    sample_values = {
        col: df[col].dropna().astype(str).unique()[:5].tolist()
        for col in df.columns
    }

    suggested_target = None
    for kw in _TARGET_KEYWORDS:
        matches = [c for c in df.columns if kw in c.lower()]
        if matches:
            suggested_target = matches[0]
            break

    suggested_protected = [
        c for c in df.columns
        if any(kw in c.lower() for kw in _PROTECTED_KEYWORDS)
    ]

    detected_positive_label = None
    if suggested_target:
        detected_positive_label = _bias_engine.detect_positive_label(df, suggested_target)

    return PreviewResponse(
        columns=list(df.columns),
        dtypes=dtypes,
        sample_values=sample_values,
        suggested_target=suggested_target,
        suggested_protected_attrs=suggested_protected,
        detected_positive_label=detected_positive_label,
        row_count=len(df),
        column_count=len(df.columns),
    )


# ── GET /analyze/history/{user_id} ───────────────────────────────────────────

@router.get("/history/{user_id}", response_model=List[AnalysisSummary])
async def get_history(user_id: str, limit: int = 20):
    try:
        db = firestore.client()
        query = (
            db.collection("audits")
            .where("user_id", "==", user_id)
            .order_by("timestamp", direction=firestore.Query.DESCENDING)
            .limit(limit)
        )
        docs = query.stream()
        summaries = []
        for doc in docs:
            data = doc.to_dict()
            summaries.append(
                AnalysisSummary(
                    audit_id=data.get("audit_id", doc.id),
                    timestamp=data.get("timestamp", ""),
                    fairness_score=data.get("fairness_score", 0.0),
                    verdict=data.get("verdict"),
                    dataset_filename=data.get("dataset_filename"),
                    at_risk_features=data.get("at_risk_features", []),
                )
            )
        return summaries
    except Exception as exc:
        logger.error("Firestore history query failed: %s", exc)
        raise HTTPException(status_code=500, detail=f"Firestore query failed: {exc}")


# ── GET /analyze/trend/{user_id} ─────────────────────────────────────────────

@router.get("/trend/{user_id}", response_model=List[TrendPoint])
async def get_trend(user_id: str, weeks: int = 12):
    """Return weekly aggregated fairness scores and verdict counts (last N weeks)."""
    try:
        db = firestore.client()
        cutoff = (datetime.now(timezone.utc) - timedelta(weeks=weeks)).isoformat()
        query = (
            db.collection("audits")
            .where("user_id", "==", user_id)
            .where("timestamp", ">=", cutoff)
            .order_by("timestamp")
        )
        docs = list(query.stream())

        week_data: Dict[str, Any] = defaultdict(
            lambda: {"scores": [], "pass": 0, "caution": 0, "fail": 0}
        )
        for doc in docs:
            data = doc.to_dict()
            raw_ts = data.get("timestamp", "")
            try:
                ts = datetime.fromisoformat(raw_ts.replace("Z", "+00:00"))
            except ValueError:
                continue
            iso = ts.isocalendar()
            week_label = f"{iso[0]}-W{iso[1]:02d}"
            week_data[week_label]["scores"].append(data.get("fairness_score", 0.0))
            verdict = (data.get("verdict") or "").upper()
            if verdict == "PASS":
                week_data[week_label]["pass"] += 1
            elif verdict == "CAUTION":
                week_data[week_label]["caution"] += 1
            elif verdict == "FAIL":
                week_data[week_label]["fail"] += 1

        points = []
        for week, wd in sorted(week_data.items()):
            avg = sum(wd["scores"]) / len(wd["scores"]) if wd["scores"] else 0.0
            points.append(TrendPoint(
                week=week,
                avg_score=round(avg, 1),
                pass_count=wd["pass"],
                caution_count=wd["caution"],
                fail_count=wd["fail"],
            ))
        return points
    except Exception as exc:
        logger.error("Trend query failed: %s", exc)
        raise HTTPException(status_code=500, detail=f"Trend query failed: {exc}")


# ── POST /analyze/batch  (ZIP of CSVs) ───────────────────────────────────────

@router.post("/batch", response_model=List[BatchSummary])
async def batch_analyze(
    request: Request,
    file: UploadFile = File(...),
    user_id: str = Form(...),
    target_column: str = Form(...),
    protected_attributes: str = Form(...),
    positive_label: str = Form(...),
    intersectional: bool = Form(False),
):
    """Accept a ZIP of CSVs and run the analysis pipeline on each file."""
    await _check_auth(request, user_id)

    content = await file.read()
    attrs = [a.strip() for a in protected_attributes.split(",") if a.strip()]

    try:
        with zipfile.ZipFile(io.BytesIO(content)) as z:
            csv_names = [
                n for n in z.namelist()
                if n.lower().endswith(".csv") and not n.startswith("__MACOSX")
            ]
    except zipfile.BadZipFile:
        raise HTTPException(status_code=400, detail="Uploaded file is not a valid ZIP archive.")

    if not csv_names:
        raise HTTPException(status_code=400, detail="No CSV files found in the ZIP archive.")

    results: List[BatchSummary] = []

    for csv_name in csv_names[:MAX_BATCH_FILES]:
        base_name = csv_name.split("/")[-1]
        try:
            with zipfile.ZipFile(io.BytesIO(content)) as z:
                csv_bytes = z.read(csv_name)

            df = _bias_engine.load_csv_from_bytes(csv_bytes)
            _bias_engine.validate_dataset(df, target_column, attrs)

            computed = await asyncio.to_thread(
                _run_analysis_sync, df, target_column, attrs, positive_label, intersectional, base_name
            )
            audit_id = str(uuid.uuid4())
            audit_result = _build_result(computed, audit_id, base_name)
            _persist_audit(audit_result, user_id)

            results.append(BatchSummary(
                filename=base_name,
                audit_id=audit_id,
                fairness_score=computed["fairness_score"],
                verdict=computed["gemini_result"].get("verdict"),
                at_risk_features=computed["at_risk"],
            ))
        except Exception as exc:
            logger.error("Batch file '%s' failed: %s", csv_name, exc)
            results.append(BatchSummary(
                filename=base_name,
                audit_id="",
                fairness_score=0.0,
                verdict=None,
                at_risk_features=[],
                error=str(exc),
            ))

    return results
