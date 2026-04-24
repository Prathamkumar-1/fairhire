import json
import logging
import os
import uuid

import firebase_admin
from dotenv import load_dotenv
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from firebase_admin import credentials
from slowapi.errors import RateLimitExceeded
from slowapi import _rate_limit_exceeded_handler

from limiter import limiter

load_dotenv()

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("fairhire")


# ── Firebase Admin SDK init ──────────────────────────────────────────────────
def _init_firebase():
    if firebase_admin._apps:
        return

    sa_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "")
    storage_bucket = os.getenv("FIREBASE_STORAGE_BUCKET", "")
    kwargs = {}
    if storage_bucket:
        kwargs["storageBucket"] = storage_bucket

    if sa_json:
        try:
            sa_dict = json.loads(sa_json)
            cred = credentials.Certificate(sa_dict)
            firebase_admin.initialize_app(cred, kwargs)
            logger.info("Firebase initialised with service account JSON.")
            return
        except Exception as exc:
            logger.warning("Could not parse FIREBASE_SERVICE_ACCOUNT_JSON: %s", exc)

    try:
        firebase_admin.initialize_app(options=kwargs if kwargs else None)
        logger.info("Firebase initialised with Application Default Credentials.")
    except Exception as exc:
        logger.warning(
            "Firebase not fully initialised: %s. "
            "Firestore/Storage will be unavailable but bias analysis will still work.",
            exc,
        )


_init_firebase()

# ── FastAPI app ───────────────────────────────────────────────────────────────
app = FastAPI(
    title="FairHire API",
    description=(
        "AI-powered bias detection for hiring datasets. "
        "Upload a CSV, get fairness metrics, and receive "
        "actionable recommendations powered by Google Gemini."
    ),
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Attach rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── CORS ─────────────────────────────────────────────────────────────────────
# Load from ALLOWED_ORIGINS env var (comma-separated). Falls back to a safe
# default that covers the production frontend + local development.
_raw_origins = os.getenv(
    "ALLOWED_ORIGINS",
    "https://fairhire-6b3d4.web.app,https://fairhire-6b3d4.firebaseapp.com,http://localhost:8000,http://localhost:3000",
)
_allowed_origins = [o.strip() for o in _raw_origins.split(",") if o.strip()]
logger.info("CORS allowed origins: %s", _allowed_origins)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    # Allow any localhost port — Flutter web uses a random port during `flutter run`
    allow_origin_regex=r"http://localhost:\d+",
)


# ── Request-ID middleware ─────────────────────────────────────────────────────
@app.middleware("http")
async def add_request_id(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4())[:8])
    logger.info("%s %s  [rid=%s]", request.method, request.url.path, request_id)
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response


# ── Routers ───────────────────────────────────────────────────────────────────
from routers.analyze import router as analyze_router  # noqa: E402
from routers.reports import router as reports_router  # noqa: E402
from routers.health import router as health_router    # noqa: E402

app.include_router(health_router)
app.include_router(analyze_router)
app.include_router(reports_router)


@app.get("/")
async def root():
    return {"service": "FairHire API", "version": "1.0.0", "docs": "/docs"}
