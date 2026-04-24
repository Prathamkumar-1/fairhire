#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# FairHire — Full deployment script
# Usage: ./deploy.sh
#
# Prerequisites (must be done once before running):
#   1. brew install --cask google-cloud-sdk
#   2. npm install -g firebase-tools
#   3. brew install --cask flutter
#   4. gcloud auth login
#   5. firebase login
#   6. Create a .env file from .env.example with real values
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
  echo "ERROR: .env file not found. Copy .env.example → .env and fill in your values."
  exit 1
fi
# shellcheck disable=SC2046
export $(grep -v '^#' .env | xargs)

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:?'GOOGLE_CLOUD_PROJECT not set in .env'}"
REGION="us-central1"
SERVICE_NAME="fairhire-backend"
IMAGE="gcr.io/$PROJECT_ID/$SERVICE_NAME"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         FairHire — Deploying to Google Cloud         ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Project : $PROJECT_ID"
echo "║  Region  : $REGION"
echo "║  Service : $SERVICE_NAME"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Validate required env vars ────────────────────────────────────────────────
REQUIRED_VARS=(
  GOOGLE_CLOUD_PROJECT
  GEMINI_API_KEY
  FIREBASE_SERVICE_ACCOUNT_JSON
  FIREBASE_STORAGE_BUCKET
  BACKEND_URL
)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done
echo "✓ All required environment variables present"

# ── Confirm ───────────────────────────────────────────────────────────────────
read -rp "Deploy to project '$PROJECT_ID'? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ═══════════════════════════════════════════════════════════════════════════
# STEP 1 — Set active GCP project
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "▶ Step 1/6 — Configuring gcloud project..."
gcloud config set project "$PROJECT_ID"
gcloud config set run/region "$REGION"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 2 — Enable APIs
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "▶ Step 2/6 — Enabling required GCP APIs..."
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  containerregistry.googleapis.com \
  aiplatform.googleapis.com \
  --quiet
echo "✓ APIs enabled"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 3 — Store secrets in Secret Manager
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "▶ Step 3/6 — Storing secrets in Secret Manager..."

_upsert_secret() {
  local name="$1"
  local value="$2"
  if gcloud secrets describe "$name" --project="$PROJECT_ID" &>/dev/null; then
    echo "$value" | gcloud secrets versions add "$name" --data-file=- --quiet
    echo "  ↻ Updated secret: $name"
  else
    echo "$value" | gcloud secrets create "$name" \
      --data-file=- \
      --replication-policy="automatic" \
      --quiet
    echo "  + Created secret: $name"
  fi
}

_upsert_secret "GEMINI_API_KEY"                 "$GEMINI_API_KEY"
_upsert_secret "FIREBASE_SERVICE_ACCOUNT_JSON"  "$FIREBASE_SERVICE_ACCOUNT_JSON"
_upsert_secret "FIREBASE_STORAGE_BUCKET"        "$FIREBASE_STORAGE_BUCKET"
_upsert_secret "GOOGLE_CLOUD_PROJECT"           "$GOOGLE_CLOUD_PROJECT"

echo "✓ Secrets stored"

# Grant Cloud Build SA access to secrets
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
CR_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "  Granting Secret Manager access to Cloud Build & Cloud Run SAs..."
for secret in GEMINI_API_KEY FIREBASE_SERVICE_ACCOUNT_JSON FIREBASE_STORAGE_BUCKET GOOGLE_CLOUD_PROJECT; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --member="serviceAccount:$CB_SA" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet 2>/dev/null || true
  gcloud secrets add-iam-policy-binding "$secret" \
    --member="serviceAccount:$CR_SA" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet 2>/dev/null || true
done
echo "✓ IAM bindings set"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 4 — Build & push Docker image, deploy to Cloud Run
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "▶ Step 4/6 — Building backend image and deploying to Cloud Run..."
echo "  (This uses Cloud Build — takes 3-5 minutes)"
echo ""

gcloud builds submit . \
  --config=cloudbuild.yaml \
  --project="$PROJECT_ID" \
  --substitutions="_REGION=$REGION,_SERVICE_NAME=$SERVICE_NAME"

echo "✓ Backend deployed to Cloud Run"

# Fetch the live URL
BACKEND_LIVE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" \
  --format='value(status.url)')
echo "  URL: $BACKEND_LIVE_URL"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 5 — Deploy Firebase rules & indexes
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "▶ Step 5/6 — Deploying Firestore rules, indexes, and Storage rules..."
firebase use "$PROJECT_ID"
firebase deploy --only firestore:rules,firestore:indexes,storage --project="$PROJECT_ID"
echo "✓ Firebase rules deployed"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 6 — Build Flutter web & deploy to Firebase Hosting
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "▶ Step 6/6 — Building Flutter web app and deploying to Firebase Hosting..."
cd frontend

# Verify firebase_options.dart has been filled in
if grep -q "YOUR_WEB_API_KEY" lib/firebase_options.dart; then
  echo ""
  echo "  ⚠ WARNING: lib/firebase_options.dart still has placeholder values."
  echo "  Run 'flutterfire configure --project=$PROJECT_ID' inside frontend/"
  echo "  then re-run this script."
  cd ..
  exit 1
fi

flutter pub get
flutter build web \
  --release \
  --dart-define=BACKEND_URL="$BACKEND_LIVE_URL"

firebase deploy --only hosting --project="$PROJECT_ID"
cd ..

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║               ✓ Deployment complete!                 ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  Backend  : %-39s ║\n" "$BACKEND_LIVE_URL"
printf "║  Frontend : https://%s.web.app%-10s ║\n" "$PROJECT_ID" ""
echo "╚══════════════════════════════════════════════════════╝"
echo ""
