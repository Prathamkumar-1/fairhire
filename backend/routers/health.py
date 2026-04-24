from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check():
    """Simple liveness probe for Cloud Run."""
    return {"status": "ok", "service": "fairhire-backend"}
