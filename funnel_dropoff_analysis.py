"""
Funnel Drop-off Analysis
Python version

Input:
    funnel_events_sample (version 1)(10).xlsx

Required sheet:
    funnel_events_sample

Required columns:
    user_id, step, timestamp
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

FILE = "funnel_events_sample (version 1)(10).xlsx"
SHEET = "funnel_events_sample"

STAGES = [
    "visited_site",
    "signup_started",
    "details_filled",
    "email_verified",
    "purchase_completed",
]

# 1. LOAD + VALIDATE
df = pd.read_excel(FILE, sheet_name=SHEET)

required = {"user_id", "step", "timestamp"}
missing = required - set(df.columns)
if missing:
    raise ValueError(f"Missing required columns: {sorted(missing)}")

df = df[["user_id", "step", "timestamp"]].copy()
df["user_id"] = df["user_id"].astype(str).str.strip()
df["step"] = df["step"].astype(str).str.strip()
df["timestamp"] = pd.to_datetime(df["timestamp"], errors="coerce")

print("Rows:", len(df))
print("Unique users:", df["user_id"].nunique())
print("Missing values:")
print(df.isna().sum())

# Duplicate events are reported, but unique-user counting prevents them
# from inflating the funnel.
duplicate_events = df.duplicated(subset=["user_id", "step"], keep=False)
print("\nDuplicate user-stage rows:", int(duplicate_events.sum()))

# 2. FUNNEL ANALYSIS
counts = (
    df.groupby("step")["user_id"]
      .nunique()
      .reindex(STAGES, fill_value=0)
)

funnel = pd.DataFrame({
    "Stage": STAGES,
    "Unique Users": counts.values
})

funnel["Previous Users"] = funnel["Unique Users"].shift(1)
funnel["Conversion Rate (%)"] = np.where(
    funnel["Previous Users"].isna(),
    100.0,
    funnel["Unique Users"] / funnel["Previous Users"] * 100
)
funnel["Users Lost"] = np.where(
    funnel["Previous Users"].isna(),
    0,
    funnel["Previous Users"] - funnel["Unique Users"]
).astype(int)
funnel["Drop-off Rate (%)"] = np.where(
    funnel["Previous Users"].isna(),
    0.0,
    funnel["Users Lost"] / funnel["Previous Users"] * 100
)

funnel["Conversion Rate (%)"] = funnel["Conversion Rate (%)"].round(2)
funnel["Drop-off Rate (%)"] = funnel["Drop-off Rate (%)"].round(2)

print("\nFINAL FUNNEL")
print(funnel[[
    "Stage", "Unique Users", "Conversion Rate (%)",
    "Users Lost", "Drop-off Rate (%)"
]].to_string(index=False))

# 3. AUTOMATIC BIGGEST DROP-OFF
drop_rows = funnel.iloc[1:].copy()
biggest_idx = drop_rows["Drop-off Rate (%)"].idxmax()
biggest = funnel.loc[biggest_idx]
previous_stage = funnel.loc[biggest_idx - 1, "Stage"]

print(
    f"\nBIGGEST DROP-OFF: {previous_stage} -> {biggest['Stage']} | "
    f"{int(biggest['Users Lost'])} users lost | "
    f"{biggest['Drop-off Rate (%)']:.2f}% drop-off"
)

overall_conversion = (
    funnel.loc[funnel["Stage"] == "purchase_completed", "Unique Users"].iloc[0]
    / funnel.loc[funnel["Stage"] == "visited_site", "Unique Users"].iloc[0]
    * 100
)
print(f"Overall Visit -> Purchase conversion: {overall_conversion:.2f}%")

# 4. FUNNEL VISUALIZATION
plt.figure(figsize=(9, 5))
bars = plt.barh(funnel["Stage"], funnel["Unique Users"])
plt.gca().invert_yaxis()
plt.title("Signup to Purchase Conversion Funnel")
plt.xlabel("Unique Users")
plt.ylabel("Stage")

for bar, value in zip(bars, funnel["Unique Users"]):
    plt.text(
        bar.get_width(),
        bar.get_y() + bar.get_height() / 2,
        f" {value}",
        va="center"
    )

plt.tight_layout()
plt.savefig("funnel_chart.png", dpi=150, bbox_inches="tight")
plt.show()

# 5. TIME-TO-CONVERT
# Keep the earliest event for duplicate user-stage records.
user_times = (
    df.groupby(["user_id", "step"])["timestamp"]
      .min()
      .unstack()
      .reindex(columns=STAGES)
)

pairs = [
    ("Visit -> Signup", "visited_site", "signup_started"),
    ("Signup -> Details", "signup_started", "details_filled"),
    ("Details -> Email", "details_filled", "email_verified"),
    ("Email -> Purchase", "email_verified", "purchase_completed"),
]

time_rows = []

for label, start, end in pairs:
    duration = (user_times[end] - user_times[start]).dt.total_seconds() / 60
    # Exclude missing stages and backwards timestamps.
    valid = duration[duration.notna() & (duration >= 0)]

    time_rows.append({
        "Transition": label,
        "Average Time (minutes)": round(valid.mean(), 2) if len(valid) else np.nan,
        "Valid Users": int(valid.count())
    })

time_analysis = pd.DataFrame(time_rows)

print("\nTIME-TO-CONVERT")
print(time_analysis.to_string(index=False))

# 6. SKIPPED-STAGE / DATA QUALITY CHECK
stage_flags = (
    df.assign(reached=1)
      .pivot_table(
          index="user_id",
          columns="step",
          values="reached",
          aggfunc="max",
          fill_value=0
      )
      .reindex(columns=STAGES, fill_value=0)
)

skip_checks = pd.DataFrame({
    "Issue": [
        "Signup without visit",
        "Details without signup",
        "Email verified without details",
        "Purchase without email verification",
    ],
    "Users": [
        int(((stage_flags["signup_started"] == 1) & (stage_flags["visited_site"] == 0)).sum()),
        int(((stage_flags["details_filled"] == 1) & (stage_flags["signup_started"] == 0)).sum()),
        int(((stage_flags["email_verified"] == 1) & (stage_flags["details_filled"] == 0)).sum()),
        int(((stage_flags["purchase_completed"] == 1) & (stage_flags["email_verified"] == 0)).sum()),
    ]
})

print("\nSKIPPED-STAGE CHECK")
print(skip_checks.to_string(index=False))

# 7. STAKEHOLDER RECOMMENDATION
print(
    "\nRECOMMENDATION:\n"
    "The largest percentage drop-off is from Details Filled to Email Verified. "
    "Reduce verification friction by sending the verification message immediately, "
    "adding a visible resend option, and offering a simple OTP or one-tap verification flow."
)

# 8. SAVE OUTPUT TABLES
funnel.to_csv("funnel_summary.csv", index=False)
time_analysis.to_csv("time_to_convert.csv", index=False)
skip_checks.to_csv("data_quality_summary.csv", index=False)

print("\nSaved: funnel_summary.csv, time_to_convert.csv, data_quality_summary.csv, funnel_chart.png")
