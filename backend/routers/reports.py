import logging

from fastapi import APIRouter, HTTPException
from firebase_admin import firestore

from models.schemas import AnalysisResult

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/reports", tags=["reports"])


@router.get("/{audit_id}", response_model=AnalysisResult)
async def get_report(audit_id: str):
    """Fetch a full audit result from Firestore by audit ID."""
    try:
        db = firestore.client()
        doc = db.collection("audits").document(audit_id).get()
    except Exception as exc:
        logger.error("Firestore read error for audit %s: %s", audit_id, exc)
        raise HTTPException(status_code=500, detail=f"Firestore error: {exc}")

    if not doc.exists:
        raise HTTPException(status_code=404, detail=f"Audit '{audit_id}' not found.")

    data = doc.to_dict()

    # Re-hydrate metrics list
    metrics = []
    for m in data.get("metrics", []):
        metrics.append(m)

    return AnalysisResult(
        audit_id=data.get("audit_id", audit_id),
        timestamp=data.get("timestamp", ""),
        fairness_score=data.get("fairness_score", 0.0),
        metrics=metrics,
        gemini_explanation=data.get("gemini_explanation", ""),
        gemini_recommendations=data.get("gemini_recommendations", []),
        at_risk_features=data.get("at_risk_features", []),
        chart_data=data.get("chart_data", {}),
        verdict=data.get("verdict"),
        verdict_reason=data.get("verdict_reason"),
        urgent_issues=data.get("urgent_issues"),
        dataset_filename=data.get("dataset_filename"),
    )


@router.delete("/{audit_id}")
async def delete_report(audit_id: str):
    """Delete an audit record from Firestore."""
    try:
        db = firestore.client()
        ref = db.collection("audits").document(audit_id)
        doc = ref.get()
        if not doc.exists:
            raise HTTPException(status_code=404, detail=f"Audit '{audit_id}' not found.")
        ref.delete()
        logger.info("Audit %s deleted from Firestore.", audit_id)
        return {"deleted": audit_id}
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Firestore delete error for audit %s: %s", audit_id, exc)
        raise HTTPException(status_code=500, detail=f"Firestore error: {exc}")
