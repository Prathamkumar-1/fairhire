"""
Generate a synthetic hiring dataset with realistic gender bias.
Run this script once to regenerate hiring_sample.csv.
"""
import random
import csv
import math

random.seed(42)

EDUCATION_LEVELS = ["High School", "Bachelor's", "Master's", "PhD"]
EDU_WEIGHTS = [0.10, 0.50, 0.30, 0.10]

N = 200

rows = []
candidate_id = 1001

for i in range(N):
    gender = "Male" if i < 130 else "Female"  # 130 male, 70 female
    age = random.randint(22, 55)
    years_exp = max(0, random.gauss(7, 4))
    years_exp = round(min(years_exp, 25), 1)

    edu = random.choices(EDUCATION_LEVELS, weights=EDU_WEIGHTS, k=1)[0]
    edu_score = EDUCATION_LEVELS.index(edu)  # 0-3

    skills_score = round(random.gauss(72, 12), 1)
    skills_score = max(30.0, min(100.0, skills_score))

    interview_score = round(random.gauss(68, 15), 1)
    interview_score = max(20.0, min(100.0, interview_score))

    # Base hiring probability from merit
    merit = (
        0.15 * (years_exp / 25)
        + 0.25 * (skills_score / 100)
        + 0.25 * (interview_score / 100)
        + 0.10 * (edu_score / 3)
    )

    # ── GENDER BIAS ──────────────────────────────────────────────────────────
    # Female candidates face a systematic 25-percentage-point penalty
    # regardless of qualifications — this makes the bias very detectable.
    if gender == "Female":
        merit -= 0.25

    # Age bias: slight penalty for candidates over 45
    if age > 45:
        merit -= 0.08

    hire_prob = max(0.02, min(0.97, merit))

    hired = 1 if random.random() < hire_prob else 0

    # Bucket age into groups for attribute analysis
    if age < 30:
        age_group = "Under 30"
    elif age < 40:
        age_group = "30-39"
    elif age < 50:
        age_group = "40-49"
    else:
        age_group = "50+"

    rows.append({
        "candidate_id": candidate_id,
        "age": age,
        "age_group": age_group,
        "gender": gender,
        "years_experience": years_exp,
        "education_level": edu,
        "skills_score": skills_score,
        "interview_score": interview_score,
        "hired": hired,
    })
    candidate_id += 1

# Shuffle so male/female candidates are interspersed
random.shuffle(rows)

fieldnames = [
    "candidate_id", "age", "age_group", "gender",
    "years_experience", "education_level",
    "skills_score", "interview_score", "hired",
]

with open("hiring_sample.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated {N} rows.")
male_rows = [r for r in rows if r["gender"] == "Male"]
female_rows = [r for r in rows if r["gender"] == "Female"]
male_hire_rate = sum(r["hired"] for r in male_rows) / len(male_rows)
female_hire_rate = sum(r["hired"] for r in female_rows) / len(female_rows)
print(f"Male hire rate:   {male_hire_rate:.1%}")
print(f"Female hire rate: {female_hire_rate:.1%}")
print(f"Disparate impact: {female_hire_rate / male_hire_rate:.3f} (should be < 0.8)")
