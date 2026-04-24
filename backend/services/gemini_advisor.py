import json
import os
import re
import logging
from typing import Dict, Any

from google import genai
from google.genai import types

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = (
    "You are a fairness and AI ethics expert. You audit ML models and datasets "
    "for bias in hiring decisions. Your goal is to explain technical bias metrics "
    "to non-technical HR managers clearly and empathetically. Always be constructive "
    "and solution-focused. Never be alarmist."
)

USER_PROMPT_TEMPLATE = """I have analyzed a hiring dataset and found the following bias metrics:
{metrics_json}

Overall Fairness Score: {score}/100

Dataset summary: {dataset_summary}

Please provide:
1. A plain-English explanation of what these results mean (2-3 sentences, no jargon, imagine explaining to an HR manager)
2. The top 3 most urgent issues found
3. Exactly 4 concrete, actionable recommendations to reduce bias
4. A one-line verdict: PASS, CAUTION, or FAIL with reason

Respond in this exact JSON format:
{{
  "explanation": "...",
  "urgent_issues": ["...", "...", "..."],
  "recommendations": ["...", "...", "...", "..."],
  "verdict": "PASS",
  "verdict_reason": "..."
}}"""


class GeminiAdvisor:
    """Wraps Google Gemini to provide plain-English bias explanations."""

    def __init__(self):
        api_key = os.getenv("GEMINI_API_KEY", "")
        if api_key:
            self._client = genai.Client(api_key=api_key)
            logger.info("GeminiAdvisor initialised with API key.")
        else:
            self._client = None
            logger.warning("GEMINI_API_KEY not set — Gemini calls will use fallback.")

    def explain_bias(
        self,
        metrics: Dict[str, Any],
        fairness_score: float,
        dataset_summary: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Send bias metrics to Gemini and return a structured explanation.
        Falls back to a rule-based explanation if the API call fails.
        """
        if self._client is None:
            return self._fallback_explanation(metrics, fairness_score)

        try:
            metrics_json = json.dumps(metrics, indent=2, default=str)
            dataset_str = json.dumps(dataset_summary, indent=2, default=str)
            prompt = USER_PROMPT_TEMPLATE.format(
                metrics_json=metrics_json,
                score=fairness_score,
                dataset_summary=dataset_str,
            )

            response = self._client.models.generate_content(
                model="gemini-2.0-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    system_instruction=SYSTEM_PROMPT,
                    temperature=0.3,
                    max_output_tokens=1024,
                    response_mime_type="application/json",
                ),
            )
            raw = response.text.strip()
            logger.info("Gemini response received (%d chars).", len(raw))

            # Strip any accidental markdown code fences (shouldn't happen with JSON mode)
            raw = re.sub(r"^```(?:json)?\s*", "", raw)
            raw = re.sub(r"\s*```$", "", raw)

            parsed = json.loads(raw)
            return self._validate_response(parsed, metrics, fairness_score)

        except json.JSONDecodeError as exc:
            logger.warning("Gemini returned invalid JSON: %s — using fallback", exc)
            return self._fallback_explanation(metrics, fairness_score)
        except Exception as exc:
            logger.warning("Gemini API call failed: %s — using fallback", exc)
            return self._fallback_explanation(metrics, fairness_score)

    def _validate_response(
        self,
        parsed: Dict[str, Any],
        metrics: Dict[str, Any],
        fairness_score: float,
    ) -> Dict[str, Any]:
        """Ensure required keys exist and fill any gaps."""
        result = {
            "explanation": parsed.get(
                "explanation",
                self._default_explanation(fairness_score),
            ),
            "urgent_issues": parsed.get("urgent_issues", [])[:3],
            "recommendations": parsed.get("recommendations", [])[:4],
            "verdict": parsed.get("verdict", self._default_verdict(fairness_score)),
            "verdict_reason": parsed.get("verdict_reason", ""),
        }

        # Ensure minimum content
        while len(result["urgent_issues"]) < 1:
            result["urgent_issues"].append("Review group-level selection rates.")
        while len(result["recommendations"]) < 4:
            result["recommendations"].append(
                "Conduct regular audits to monitor fairness over time."
            )

        # Normalise verdict to uppercase
        if result["verdict"]:
            result["verdict"] = result["verdict"].upper().strip()
            if result["verdict"] not in ("PASS", "CAUTION", "FAIL"):
                result["verdict"] = self._default_verdict(fairness_score)

        return result

    def _fallback_explanation(
        self, metrics: Dict[str, Any], fairness_score: float
    ) -> Dict[str, Any]:
        """Rule-based fallback when Gemini is unavailable."""
        failing_attrs = []
        for attr, attr_data in metrics.items():
            if "error" in attr_data:
                continue
            failed_checks = [
                k for k in ["disparate_impact", "demographic_parity_diff", "equalized_odds_diff"]
                if not attr_data.get(k, {}).get("passed", True)
            ]
            if failed_checks:
                failing_attrs.append(attr)

        verdict = self._default_verdict(fairness_score)
        explanation = self._default_explanation(fairness_score)

        urgent_issues = []
        for attr in failing_attrs[:3]:
            urgent_issues.append(
                f"Significant bias detected in '{attr}' — selection rates differ meaningfully across groups."
            )
        if not urgent_issues:
            urgent_issues = ["No major bias signals detected. Continue monitoring."]

        recommendations = [
            "Review and anonymize protected attributes during the initial screening phase.",
            "Implement structured interviews with standardized scoring rubrics.",
            "Conduct regular bias audits (at least quarterly) on hiring outcomes.",
            "Train recruiters on unconscious bias and evidence-based hiring practices.",
        ]

        return {
            "explanation": explanation,
            "urgent_issues": urgent_issues,
            "recommendations": recommendations,
            "verdict": verdict,
            "verdict_reason": f"Fairness score of {fairness_score:.0f}/100.",
        }

    @staticmethod
    def _default_verdict(score: float) -> str:
        if score >= 80:
            return "PASS"
        elif score >= 60:
            return "CAUTION"
        return "FAIL"

    @staticmethod
    def _default_explanation(score: float) -> str:
        if score >= 80:
            return (
                "Your hiring dataset shows a generally fair distribution of outcomes "
                "across protected groups. Minor differences exist but are within acceptable ranges."
            )
        elif score >= 60:
            return (
                "Your hiring dataset shows some concerning disparities between protected groups. "
                "While not critically imbalanced, these patterns warrant attention and process review."
            )
        return (
            "Your hiring dataset shows significant disparities in selection rates across protected "
            "groups. Immediate review of your hiring process is recommended to ensure fairness."
        )
