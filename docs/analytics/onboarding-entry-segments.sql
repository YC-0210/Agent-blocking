-- One row per installation for integration with the existing retention query.
-- Purpose/habit arrays use stable IDs. Arrays contain 'unknown' if no complete
-- questionnaire was submitted before the first successful locking-session start.
-- Use the same environment, metric version and cohort window as the retention
-- denominator. Do NOT replace missing responses with a later/current profile.
WITH cohorts AS (
    SELECT
        distinct_id,
        properties.environment AS environment,
        min(timestamp) AS cohort_started_at
    FROM events
    WHERE event = 'retention_cohort_entered'
      AND properties.environment = 'production'
      AND properties.is_synthetic = false
      AND properties.metric_version = 1
      AND timestamp >= now() - INTERVAL 90 DAY
    GROUP BY distinct_id, environment
), submitted AS (
    SELECT distinct_id, timestamp, properties
    FROM events
    WHERE event = 'onboarding_answers_submitted'
      AND properties.environment = 'production'
      AND properties.is_synthetic = false
      AND properties.questionnaire_version = 1
      AND distinct_id IN (SELECT distinct_id FROM cohorts)
), entry AS (
    SELECT
        c.distinct_id,
        c.environment,
        c.cohort_started_at,
        argMaxIf(
            tuple(a.properties.purposes, a.properties.scrolling_habits,
                  a.properties.daily_phone_time, a.properties.event_id),
            tuple(a.timestamp, toInt(a.properties.response_revision), a.properties.event_id),
            a.timestamp <= c.cohort_started_at AND a.properties.event_id IS NOT NULL
        ) AS snapshot
    FROM cohorts c
    LEFT JOIN submitted a ON c.distinct_id = a.distinct_id
    GROUP BY c.distinct_id, c.environment, c.cohort_started_at
), decoded AS (
    SELECT
        distinct_id, environment, cohort_started_at,
        JSONExtract(ifNull(tupleElement(snapshot, 1), '[]'), 'Array(String)') AS purposes,
        JSONExtract(ifNull(tupleElement(snapshot, 2), '[]'), 'Array(String)') AS habits,
        tupleElement(snapshot, 3) AS phone_time,
        tupleElement(snapshot, 4) AS response_event_id
    FROM entry
)
SELECT
    distinct_id, environment, cohort_started_at, response_event_id,
    if(empty(purposes), ['unknown'], purposes) AS entry_purposes,
    if(empty(habits), ['unknown'], habits) AS entry_habits,
    ifNull(phone_time, 'unknown') AS entry_daily_phone_time
FROM decoded
ORDER BY cohort_started_at, distinct_id
