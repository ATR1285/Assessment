-- Funnel Drop-off Analysis — SQLite
-- Source structure used in SQLite Online:
--   c1 = user_id
--   c2 = step
--   c3 = timestamp
--
-- Funnel order:
-- visited_site -> signup_started -> details_filled -> email_verified -> purchase_completed

-- ============================================================
-- 1) DATA QUALITY CHECK
-- ============================================================
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT c1) AS unique_users,
    SUM(CASE WHEN c1 IS NULL OR TRIM(c1) = '' THEN 1 ELSE 0 END) AS missing_user_id,
    SUM(CASE WHEN c2 IS NULL OR TRIM(c2) = '' THEN 1 ELSE 0 END) AS missing_step,
    SUM(CASE WHEN c3 IS NULL OR TRIM(c3) = '' THEN 1 ELSE 0 END) AS missing_timestamp
FROM funnel_events_sample
WHERE c1 <> 'user_id';

-- Duplicate user-stage events.
SELECT
    c1 AS user_id,
    c2 AS stage,
    COUNT(*) AS event_count
FROM funnel_events_sample
WHERE c1 <> 'user_id'
GROUP BY c1, c2
HAVING COUNT(*) > 1
ORDER BY event_count DESC, user_id, stage;

-- ============================================================
-- 2) FINAL FUNNEL TABLE
--    COUNT(DISTINCT user_id) prevents duplicate events from
--    inflating stage counts.
-- ============================================================
WITH stage_order(stage, stage_no) AS (
    VALUES
        ('visited_site', 1),
        ('signup_started', 2),
        ('details_filled', 3),
        ('email_verified', 4),
        ('purchase_completed', 5)
),
stage_counts AS (
    SELECT
        s.stage,
        s.stage_no,
        COUNT(DISTINCT f.c1) AS unique_users
    FROM stage_order s
    LEFT JOIN funnel_events_sample f
        ON f.c2 = s.stage
       AND f.c1 <> 'user_id'
    GROUP BY s.stage, s.stage_no
),
funnel AS (
    SELECT
        stage,
        stage_no,
        unique_users,
        LAG(unique_users) OVER (ORDER BY stage_no) AS previous_users
    FROM stage_counts
)
SELECT
    stage,
    unique_users,
    CASE
        WHEN previous_users IS NULL THEN 100.00
        ELSE ROUND(unique_users * 100.0 / previous_users, 2)
    END AS conversion_rate_pct,
    CASE
        WHEN previous_users IS NULL THEN 0
        ELSE previous_users - unique_users
    END AS users_lost,
    CASE
        WHEN previous_users IS NULL THEN 0.00
        ELSE ROUND((previous_users - unique_users) * 100.0 / previous_users, 2)
    END AS drop_off_rate_pct
FROM funnel
ORDER BY stage_no;

-- ============================================================
-- 3) AUTOMATIC BIGGEST DROP-OFF FLAG
-- ============================================================
WITH stage_order(stage, stage_no) AS (
    VALUES
        ('visited_site', 1),
        ('signup_started', 2),
        ('details_filled', 3),
        ('email_verified', 4),
        ('purchase_completed', 5)
),
stage_counts AS (
    SELECT s.stage, s.stage_no, COUNT(DISTINCT f.c1) AS unique_users
    FROM stage_order s
    LEFT JOIN funnel_events_sample f
        ON f.c2 = s.stage
       AND f.c1 <> 'user_id'
    GROUP BY s.stage, s.stage_no
),
x AS (
    SELECT
        stage,
        stage_no,
        unique_users,
        LAG(stage) OVER (ORDER BY stage_no) AS previous_stage,
        LAG(unique_users) OVER (ORDER BY stage_no) AS previous_users
    FROM stage_counts
),
dropoffs AS (
    SELECT
        previous_stage || ' -> ' || stage AS transition,
        previous_users - unique_users AS users_lost,
        ROUND((previous_users - unique_users) * 100.0 / previous_users, 2) AS drop_off_rate_pct
    FROM x
    WHERE previous_users IS NOT NULL
)
SELECT
    transition AS biggest_drop_off_transition,
    users_lost,
    drop_off_rate_pct
FROM dropoffs
ORDER BY drop_off_rate_pct DESC, users_lost DESC
LIMIT 1;

-- ============================================================
-- 4) OVERALL VISIT -> PURCHASE CONVERSION
-- ============================================================
SELECT
    COUNT(DISTINCT CASE WHEN c2 = 'visited_site' THEN c1 END) AS visitors,
    COUNT(DISTINCT CASE WHEN c2 = 'purchase_completed' THEN c1 END) AS purchasers,
    ROUND(
        COUNT(DISTINCT CASE WHEN c2 = 'purchase_completed' THEN c1 END) * 100.0 /
        NULLIF(COUNT(DISTINCT CASE WHEN c2 = 'visited_site' THEN c1 END), 0),
        2
    ) AS overall_conversion_pct
FROM funnel_events_sample
WHERE c1 <> 'user_id';

-- ============================================================
-- 5) USER-LEVEL STAGE FLAGS
--    Useful for skipped-step/data-quality investigation.
-- ============================================================
WITH users AS (
    SELECT
        c1 AS user_id,
        MAX(CASE WHEN c2 = 'visited_site' THEN 1 ELSE 0 END) AS visited,
        MAX(CASE WHEN c2 = 'signup_started' THEN 1 ELSE 0 END) AS signup,
        MAX(CASE WHEN c2 = 'details_filled' THEN 1 ELSE 0 END) AS details,
        MAX(CASE WHEN c2 = 'email_verified' THEN 1 ELSE 0 END) AS verified,
        MAX(CASE WHEN c2 = 'purchase_completed' THEN 1 ELSE 0 END) AS purchased
    FROM funnel_events_sample
    WHERE c1 <> 'user_id'
    GROUP BY c1
)
SELECT *
FROM users
ORDER BY user_id;

-- ============================================================
-- 6) TIME-TO-CONVERT
--    MIN(timestamp) handles duplicate user-stage events.
--    Only chronological pairs (next >= previous) are valid.
-- ============================================================
WITH user_times AS (
    SELECT
        c1 AS user_id,
        MIN(CASE WHEN c2 = 'visited_site' THEN c3 END) AS visited_time,
        MIN(CASE WHEN c2 = 'signup_started' THEN c3 END) AS signup_time,
        MIN(CASE WHEN c2 = 'details_filled' THEN c3 END) AS details_time,
        MIN(CASE WHEN c2 = 'email_verified' THEN c3 END) AS verified_time,
        MIN(CASE WHEN c2 = 'purchase_completed' THEN c3 END) AS purchase_time
    FROM funnel_events_sample
    WHERE c1 <> 'user_id'
    GROUP BY c1
),
transitions AS (
    SELECT 'Visit -> Signup' AS transition,
           (julianday(signup_time) - julianday(visited_time)) * 1440.0 AS minutes
    FROM user_times
    WHERE visited_time IS NOT NULL AND signup_time IS NOT NULL AND signup_time >= visited_time

    UNION ALL

    SELECT 'Signup -> Details',
           (julianday(details_time) - julianday(signup_time)) * 1440.0
    FROM user_times
    WHERE signup_time IS NOT NULL AND details_time IS NOT NULL AND details_time >= signup_time

    UNION ALL

    SELECT 'Details -> Email',
           (julianday(verified_time) - julianday(details_time)) * 1440.0
    FROM user_times
    WHERE details_time IS NOT NULL AND verified_time IS NOT NULL AND verified_time >= details_time

    UNION ALL

    SELECT 'Email -> Purchase',
           (julianday(purchase_time) - julianday(verified_time)) * 1440.0
    FROM user_times
    WHERE verified_time IS NOT NULL AND purchase_time IS NOT NULL AND purchase_time >= verified_time
)
SELECT
    transition,
    COUNT(*) AS valid_users,
    ROUND(AVG(minutes), 2) AS average_minutes
FROM transitions
GROUP BY transition
ORDER BY CASE transition
    WHEN 'Visit -> Signup' THEN 1
    WHEN 'Signup -> Details' THEN 2
    WHEN 'Details -> Email' THEN 3
    WHEN 'Email -> Purchase' THEN 4
END;

-- ============================================================
-- 7) STAKEHOLDER SUMMARY / RECOMMENDATION
-- ============================================================
-- Expected funnel result for the supplied workbook:
-- visited_site:       200 users, 100.00% conversion
-- signup_started:     150 users,  75.00% conversion, 50 lost, 25.00% drop-off
-- details_filled:      96 users,  64.00% conversion, 54 lost, 36.00% drop-off
-- email_verified:      52 users,  54.17% conversion, 44 lost, 45.83% drop-off
-- purchase_completed:  44 users,  84.62% conversion,  8 lost, 15.38% drop-off
--
-- Biggest percentage drop-off:
-- details_filled -> email_verified = 45.83% (44 users lost)
--
-- Overall visit -> purchase conversion = 22.00%.
--
-- Recommendation:
-- The largest funnel leak occurs between Details Filled and Email Verified.
-- Reduce verification friction by sending the verification message immediately,
-- adding a clear resend option, and offering a simple OTP/one-tap verification flow.
--
-- Data-quality note:
-- The supplied timestamps do not form valid chronological pairs for every stage.
-- The time-to-convert query therefore excludes missing or backwards transitions
-- instead of reporting misleading negative durations.
