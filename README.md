# Funnel Drop-off Analysis

## Project Overview

This project analyzes event-level data from a signup and checkout
funnel. Each record contains a `user_id`, the stage reached by the user,
and a timestamp.

The funnel follows this sequence:

`visited_site → signup_started → details_filled → email_verified → purchase_completed`

The main objective is to calculate the number of unique users at each
stage, measure stage-to-stage conversion rates, identify where users
drop off the most, and present the result in a way that can support
product or growth decisions.

## Tools Used

-   Microsoft Excel
-   SQLite
-   Python
-   Pandas
-   Matplotlib

## Dataset

The analysis uses the `funnel_events_sample` dataset with the following
fields:

-   `user_id` --- identifies each user
-   `step` --- identifies the funnel stage reached
-   `timestamp` --- records the time of the event

## Approach

I completed the analysis in three parts.

### 1. Excel Analysis

Excel was used to inspect the raw data, calculate the funnel metrics,
create a funnel visualization, and investigate time between stages.

The funnel was kept in its fixed business order rather than sorting the
stages alphabetically.

### 2. SQLite Analysis

SQLite was used to reproduce the funnel analysis with queries. Unique
users were counted at each stage so that duplicate events would not
incorrectly increase the funnel counts.

The SQL analysis also includes data-quality checks, automatic drop-off
identification, user-level stage flags, and time-to-convert logic.

### 3. Python Analysis

Python was used to validate the results programmatically. Pandas was
used for data preparation and aggregation, while Matplotlib was used to
create a funnel chart.

The Python analysis also checks duplicates, skipped stages,
chronological timestamp validity, and automatically identifies the
largest drop-off.

## Final Funnel Results

  Stage                  Unique Users   Conversion Rate   Users Lost   Drop-off Rate
  -------------------- -------------- ----------------- ------------ ---------------
  Visited Site                    200           100.00%            0           0.00%
  Signup Started                  150            75.00%           50          25.00%
  Details Filled                   96            64.00%           54          36.00%
  Email Verified                   52            54.17%           44          45.83%
  Purchase Completed               44            84.62%            8          15.38%

The overall Visit → Purchase conversion rate is **22.00%**.

## Key Insight

The largest percentage drop-off occurs between:

**Details Filled → Email Verified**

At this transition, **44 users were lost**, representing a **45.83%
drop-off rate** from the previous stage.

This suggests that email verification is the strongest friction point in
the current funnel.

## Recommendation

The verification process should be reviewed first. A practical
improvement would be to send the verification message immediately after
details are submitted, provide a clearly visible resend option, and
consider a simpler OTP or one-tap verification process.

After making the change, the Details Filled → Email Verified conversion
rate should be monitored to determine whether the improvement reduces
abandonment.

## Bonus Analysis

### Funnel Visualization

A funnel/bar visualization was created to make the decrease in users
across stages easy to understand for a non-technical stakeholder.

### Automated Drop-off Identification

The SQL and Python analyses automatically calculate the drop-off rates
and identify the largest funnel leak instead of requiring the analyst to
select it manually.

### Time-to-Convert

Timestamp analysis was attempted between consecutive stages.

Valid chronological data produced:

-   Visit → Signup: approximately **21.15 minutes**, based on **124
    valid users**
-   Signup → Details: approximately **15.79 minutes**, based on **33
    valid users**

The later transitions could not be reliably averaged because the
supplied timestamps did not provide valid chronological stage pairs for
those calculations. Instead of reporting misleading negative or invalid
durations, those records were excluded.

## Data Quality Handling

Unique users are counted at each funnel stage, so repeated events for
the same user and stage do not inflate the funnel.

For time analysis, the earliest timestamp for a user at a stage is used
when duplicate user-stage events exist.

Users who skip a stage are not forced into that transition. A time
difference is calculated only when both consecutive stages exist and the
second timestamp is equal to or later than the first timestamp.

This keeps the funnel counts and time analysis separate: a user can
still be counted as having reached a stage even when their timestamps
cannot be used for a valid time-to-convert calculation.

## Challenges Faced and How I Handled Them

### 1. Excel Formula References

One of the main difficulties was getting the Excel formulas to reference
the correct raw-data source. Some formulas initially depended on table
references such as `Table1`, while the actual source data was available
in the `funnel_events_sample` worksheet.

**How I handled it:**\
I checked the actual sheet structure and used consistent references to
the raw-data columns for user ID, stage, and timestamp. I also tested
formulas on individual users before filling them down across the sheet.

### 2. Blank Values Were Initially Confusing

Some users did not reach later stages such as `email_verified` or
`purchase_completed`. Their corresponding cells were blank, which could
initially look like a formula problem.

**How I handled it:**\
I treated missing later-stage values as valid funnel behavior rather
than replacing them with artificial values. Blank cells remain blank
when the user never reached that stage.

### 3. Number and Time Formatting in Excel

Excel sometimes displayed counts as times, such as `2976:00`, because
cells containing numeric counts had inherited a time format.

**How I handled it:**\
I separated formatting by purpose. Timestamp and duration fields use
time formats, while user counts use General/Number and
conversion/drop-off rates use percentage formats.

### 4. Duplicate Events

Event-level datasets can contain more than one event for the same user
and stage. Counting rows directly could therefore overstate the number
of users reaching a stage.

**How I handled it:**\
The funnel analysis counts unique `user_id` values per stage. For
timestamp analysis, the earliest stage timestamp is used so repeated
user-stage events do not create multiple conversion durations.

### 5. Users Skipping Funnel Stages

Not every user's event history follows the complete five-stage sequence.
A user may have a later event even when a previous event is missing.

**How I handled it:**\
Stage reach and transition analysis were treated separately. The user is
counted at every stage they actually reached, but a stage-to-stage time
is calculated only when both required consecutive events are present.

### 6. Timestamp Sequence Problems

The biggest data-quality challenge appeared in the time-to-convert
analysis. Some timestamps did not form a valid chronological sequence.
Subtracting these timestamps directly could create negative or
misleading durations.

**How I handled it:**\
I added validation so that a transition is included only when both
timestamps exist and the later funnel stage has a timestamp greater than
or equal to the earlier stage. Invalid pairs are excluded instead of
being changed or assumed.

Because of this, the final two time transitions do not report an average
when there are no valid chronological pairs.

### 7. Keeping Results Consistent Across Excel, SQL, and Python

The project uses three different tools, so inconsistent logic could
easily produce different answers.

**How I handled it:**\
I used the same fixed funnel sequence and the same unique-user
definition across all three approaches. The core funnel counts were
cross-checked as:

`200 → 150 → 96 → 52 → 44`

This confirmed that the primary funnel analysis was consistent.

## What I Learned

This project showed that funnel analysis is not only about calculating
percentages. Data quality, duplicate handling, stage ordering, missing
events, timestamp validation, and clear communication all affect whether
the final insight is trustworthy.

The most important lesson was to validate the underlying data before
interpreting a metric. When the timestamps were inconsistent, I kept the
reliable funnel results and clearly separated them from the time
analysis rather than forcing an incorrect result.

## Files

-   Excel workbook --- funnel analysis and visualization
-   `.sql` file --- SQLite funnel analysis and validation queries
-   `.py` file --- Python analysis, visualization, data-quality checks,
    and validation
