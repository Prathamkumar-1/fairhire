# FairHire

> AI-powered bias detection platform for fairer hiring — Google Solution Challenge 2026

FairHire helps HR teams upload hiring datasets, detect algorithmic bias against protected groups (gender, age, race, etc.), visualise the results, and receive actionable recommendations powered by Google Gemini.

---

## Problem Statement

Hiring algorithms and manual processes often perpetuate systemic discrimination. Studies show that identical resumes receive 30–40% fewer callbacks when the applicant is perceived as a minority. Most organisations have no tooling to measure or address this. FairHire makes bias detection accessible to every HR team — no data science background required.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      FLUTTER WEB (Frontend)                  │
│  Login → Dashboard → Analyze Wizard → Report + Charts        │
│  Firebase Auth (Google Sign-In)  │  Firebase Storage (CSV)   │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTPS / REST
┌────────────────────────▼────────────────────────────────────┐
│              FASTAPI BACKEND (Google Cloud Run)              │
│                                                              │
│  ┌─────────────┐  ┌──────────────────┐  ┌────────────────┐  │
│  │ BiasEngine  │  │  GeminiAdvisor   │  │ VertexEvaluator│  │
│  │ (Fairlearn) │  │ (gemini-1.5-flash│  │  (Vertex AI)   │  │
│  └─────────────┘  └──────────────────┘  └────────────────┘  │
│                                                              │
│  Firebase Admin SDK (Firestore audit logs + Storage)         │
└─────────────────────────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                  GOOGLE CLOUD INFRASTRUCTURE                  │
│  Cloud Run  │  Cloud Build (CI/CD)  │  Secret Manager        │
│  Firestore  │  Firebase Storage     │  Vertex AI             │
└─────────────────────────────────────────────────────────────┘
```

---

## UN Sustainable Development Goals

| SDG | Goal | How FairHire contributes |
|-----|------|--------------------------|
| **SDG 10** | Reduced Inequalities | Detects and helps eliminate systematic discrimination in hiring, directly reducing economic inequality for marginalised groups. |
| **SDG 8** | Decent Work & Economic Growth | Promotes fair access to employment opportunities regardless of gender, age, race, or other protected characteristics. |

---

## Google Technologies Used

| Technology | Purpose | Why chosen |
|------------|---------|------------|
| **Google Cloud Run** | Hosts the FastAPI backend | Serverless, auto-scaling, pay-per-request — ideal for burst analysis workloads |
| **Firebase Authentication** | Google Sign-In for HR users | Zero-friction auth with enterprise Google Workspace accounts |
| **Firebase Firestore** | Stores audit logs and results | Real-time sync, serverless, no schema migrations needed |
| **Firebase Storage** | Stores uploaded CSV datasets | Integrated with Firebase Auth rules for per-user file isolation |
| **Google Gemini 1.5 Flash** | AI fairness advisor | Best-in-class multimodal reasoning; explains technical metrics to non-technical HR managers |
| **Vertex AI** | Model evaluation (feature importance, group predictions) | Enterprise MLOps platform with built-in Explainability tools |
| **Google Cloud Build** | CI/CD pipeline | Native GCP integration; builds, pushes, and deploys in one YAML |
| **Secret Manager** | Secure env var storage | Keeps API keys and service account JSON out of container images |
| **Flutter Web** | Cross-platform frontend | Single Dart codebase deployable to web, iOS, and Android |

---

## Local Setup

### Prerequisites

- Python 3.11+
- Flutter 3.22+ with web support enabled (`flutter config --enable-web`)
- A Firebase project with Auth, Firestore, and Storage enabled
- A Google Gemini API key (from Google AI Studio)

### Backend

```bash
cd backend

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy and fill in environment variables
cp ../.env.example .env
# Edit .env with your actual keys

# Start the server
uvicorn main:app --reload --port 8000
```

The API will be live at http://localhost:8000. Visit http://localhost:8000/docs for the interactive Swagger UI.

### Frontend

```bash
cd frontend

# Install Flutter dependencies
flutter pub get

# Edit lib/firebase_options.dart with your Firebase project config
# (or run: flutterfire configure --project=YOUR_PROJECT_ID)

# Start the Flutter web dev server
flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8000
```

---

## Deploying to Google Cloud

### One-time setup

```bash
# Authenticate
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  secretmanager.googleapis.com aiplatform.googleapis.com

# Store secrets
echo -n "your_gemini_key" | gcloud secrets create GEMINI_API_KEY --data-file=-
echo -n '{"type":"service_account",...}' | gcloud secrets create FIREBASE_SERVICE_ACCOUNT_JSON --data-file=-
echo -n "your_project.appspot.com" | gcloud secrets create FIREBASE_STORAGE_BUCKET --data-file=-
echo -n "your_project_id" | gcloud secrets create GOOGLE_CLOUD_PROJECT --data-file=-

# Grant Cloud Build access to secrets
PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID --format='value(projectNumber)')
gcloud secrets add-iam-policy-binding GEMINI_API_KEY \
  --member="serviceAccount:$PROJECT_NUMBER@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
# Repeat for other secrets
```

### Deploy

```bash
# From the repo root — Cloud Build handles everything
gcloud builds submit . --config=cloudbuild.yaml
```

### Frontend (Firebase Hosting)

```bash
cd frontend
flutter build web --dart-define=BACKEND_URL=https://fairhire-backend-xxxx-uc.a.run.app
firebase deploy --only hosting
```

---

## Running a Bias Analysis

### Sample CSV format

```csv
candidate_id,age,gender,years_experience,education_level,skills_score,interview_score,hired
1001,29,Male,4.5,Bachelor's,82.3,74.1,1
1002,34,Female,6.0,Master's,79.1,81.2,0
1003,41,Male,12.0,Bachelor's,68.7,63.4,1
```

Required columns:
- At least one **outcome column** (e.g. `hired`, `selected`, `passed`) with binary values
- At least one **protected attribute** column (e.g. `gender`, `age_group`, `race`)

### Via the UI

1. Sign in with Google
2. Click **Start New Audit**
3. Upload your CSV file
4. Select the target column and protected attributes to check
5. Click **Run Analysis** — Gemini will explain the results in plain English

### Via the API directly

```bash
curl -X POST http://localhost:8000/analyze/upload-and-analyze \
  -F "file=@sample_data/hiring_sample.csv" \
  -F "user_id=demo_user" \
  -F "target_column=hired" \
  -F "protected_attributes=gender,age_group" \
  -F "positive_label=1"
```

Or use the bundled test script:

```bash
cd backend
python3 sample_data/test_analysis.py
```

---

## Bias Metrics Explained

### Disparate Impact Ratio (4/5ths Rule)
The ratio of the selection rate of the least-favoured group to the most-favoured group. Under US EEOC guidelines, a ratio below **0.8** signals potential adverse impact.

*Formula: min(group_selection_rates) / max(group_selection_rates)*

### Demographic Parity Difference
The difference in selection rates between the most and least advantaged groups. Values above **±0.1** indicate meaningful disparity.

*Formula: max(group_selection_rates) − min(group_selection_rates)*

### Equalized Odds Difference
The maximum difference in true-positive rates and false-positive rates across groups. Captures whether a model makes equally good decisions for all groups. Values above **±0.1** are flagged.

### Selection Rate
The proportion of candidates in a group who received a positive outcome (e.g. hired = 1). Displayed per group in the bar charts for easy visual comparison.

### Fairness Score (0–100)
An overall score computed as:

```
Fairness Score = 100 × (checks passed / total checks)
```

A score of 80+ is a PASS, 60–79 is CAUTION, and below 60 is FAIL.

---

## Project Structure

```
fairhire/
├── backend/
│   ├── main.py                    FastAPI app entry point
│   ├── routers/
│   │   ├── analyze.py             Upload + analysis endpoints
│   │   ├── reports.py             Report fetch/delete
│   │   └── health.py              /health liveness probe
│   ├── services/
│   │   ├── bias_engine.py         Fairlearn metric computation
│   │   ├── gemini_advisor.py      Gemini AI explanation layer
│   │   └── vertex_evaluator.py    Vertex AI model evaluation
│   ├── models/
│   │   └── schemas.py             Pydantic request/response models
│   ├── sample_data/
│   │   ├── hiring_sample.csv      200-row synthetic dataset with gender bias
│   │   └── test_analysis.py       End-to-end smoke test script
│   ├── requirements.txt
│   └── Dockerfile
├── frontend/
│   ├── lib/
│   │   ├── main.dart              App entry point + GoRouter
│   │   ├── firebase_options.dart  Firebase config (fill in your values)
│   │   ├── screens/
│   │   │   ├── login_screen.dart
│   │   │   ├── dashboard_screen.dart
│   │   │   ├── analyze_screen.dart   3-step wizard
│   │   │   ├── report_screen.dart    Full report with charts
│   │   │   └── history_screen.dart
│   │   ├── services/
│   │   │   ├── api_service.dart
│   │   │   └── auth_service.dart
│   │   ├── models/
│   │   │   └── analysis_models.dart
│   │   ├── widgets/
│   │   │   ├── fairness_score_ring.dart
│   │   │   ├── metric_row.dart
│   │   │   ├── bias_bar_chart.dart
│   │   │   ├── gemini_advisor_card.dart
│   │   │   └── audit_list_tile.dart
│   │   └── theme/
│   │       └── app_theme.dart
│   ├── web/index.html
│   └── pubspec.yaml
├── cloudbuild.yaml
├── .env.example
└── README.md
```

---

## Team

| Name | Role |
|------|------|
| *(Your name here)* | Full-Stack Engineer |
| *(Team member 2)* | ML / Bias Analysis |
| *(Team member 3)* | UI/UX Designer |
| *(Team member 4)* | Cloud Infrastructure |

---

*Built for the Google Solution Challenge 2026. Addressing UN SDGs 8 and 10.*
