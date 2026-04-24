"""
End-to-end smoke test for the FairHire API.

Usage:
    # Start the backend first:
    #   cd backend && uvicorn main:app --reload --port 8000
    #
    # Then in another terminal:
    #   python sample_data/test_analysis.py [--url http://localhost:8000]

The script uploads hiring_sample.csv to the /analyze/upload-and-analyze
endpoint (no Firebase Storage required) and prints a formatted report.
"""
import argparse
import json
import sys
from pathlib import Path

import requests

BASE_URL = "http://localhost:8000"
CSV_PATH = Path(__file__).parent / "hiring_sample.csv"


def run_test(base_url: str) -> None:
    print(f"\n{'='*60}")
    print("  FairHire API — End-to-End Test")
    print(f"{'='*60}\n")

    # ── Health check ─────────────────────────────────────────────────────────
    print("1. Health check …")
    r = requests.get(f"{base_url}/health", timeout=10)
    r.raise_for_status()
    print(f"   ✓ {r.json()}\n")

    # ── Upload & analyse ──────────────────────────────────────────────────────
    print("2. Running bias analysis on hiring_sample.csv …")
    with open(CSV_PATH, "rb") as fh:
        resp = requests.post(
            f"{base_url}/analyze/upload-and-analyze",
            files={"file": ("hiring_sample.csv", fh, "text/csv")},
            data={
                "user_id": "test_user_001",
                "target_column": "hired",
                "protected_attributes": "gender,age_group",
                "positive_label": "1",
            },
            timeout=120,
        )

    if resp.status_code != 200:
        print(f"   ✗ API returned {resp.status_code}")
        print(f"   {resp.text}")
        sys.exit(1)

    result = resp.json()

    # ── Print report ──────────────────────────────────────────────────────────
    print(f"\n{'─'*60}")
    print(f"  Audit ID      : {result['audit_id']}")
    print(f"  Timestamp     : {result['timestamp']}")
    print(f"  Fairness Score: {result['fairness_score']:.1f} / 100")
    print(f"  Verdict       : {result.get('verdict', 'N/A')}")
    print(f"  Verdict Reason: {result.get('verdict_reason', 'N/A')}")
    print(f"  At-Risk Attrs : {', '.join(result['at_risk_features']) or 'None'}")
    print(f"{'─'*60}\n")

    print("BIAS METRICS:")
    for m in result["metrics"]:
        status = "✓ PASS" if m["passed"] else "✗ FAIL"
        print(f"  [{status}] {m['name']}")
        print(f"           value={m['value']:.4f}  threshold={m['threshold']}")

    print(f"\nGEMINI AI EXPLANATION:")
    print(f"  {result['gemini_explanation']}\n")

    if result.get("urgent_issues"):
        print("URGENT ISSUES:")
        for issue in result["urgent_issues"]:
            print(f"  ⚠  {issue}")
        print()

    print("RECOMMENDATIONS:")
    for i, rec in enumerate(result["gemini_recommendations"], 1):
        print(f"  {i}. {rec}")

    print(f"\nCHART DATA (selection rates):")
    for attr, data in result["chart_data"].items():
        print(f"\n  {attr}:")
        for grp, rate in zip(data["groups"], data["selection_rates"]):
            bar = "█" * int(rate * 30)
            print(f"    {grp:<15} {rate:.3f}  {bar}")

    print(f"\n{'='*60}")
    print("  ✓ All checks passed — API is working correctly")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FairHire API smoke test")
    parser.add_argument(
        "--url",
        default=BASE_URL,
        help="Base URL of the running FairHire backend (default: http://localhost:8000)",
    )
    args = parser.parse_args()
    run_test(args.url)
