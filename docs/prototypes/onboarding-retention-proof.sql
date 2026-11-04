WITH scoped AS (
  SELECT distinct_id, event, timestamp, properties
  FROM events
  WHERE distinct_id LIKE 'retention-upload-test-onboarding-b280026b-%'
    AND timestamp >= now() - INTERVAL 12 DAY
    AND properties.environment = 'development'
    AND properties.is_synthetic = true
), cohort AS (
  SELECT distinct_id, min(timestamp) AS started_at
  FROM scoped WHERE event = 'retention_cohort_entered' GROUP BY distinct_id
), entry AS (
  SELECT c.distinct_id,
    argMaxIf(tuple(a.properties.purposes, a.properties.scrolling_habits, a.properties.daily_phone_time),
      tuple(a.timestamp, toInt(a.properties.response_revision)),
      a.event = 'onboarding_answers_submitted' AND a.timestamp <= c.started_at) AS answers
  FROM cohort c LEFT JOIN scoped a ON c.distinct_id = a.distinct_id
  GROUP BY c.distinct_id
), latest_contributions AS (
  SELECT distinct_id, properties.contribution_key AS contribution_key,
    toInt(properties.period_index) AS period_index,
    argMax(toFloat(properties.locked_seconds), toInt(properties.revision)) AS seconds
  FROM scoped WHERE event = 'retention_locked_time_contributed'
  GROUP BY distinct_id, contribution_key, period_index
), totals AS (
  SELECT distinct_id, sumIf(seconds, period_index = 1) AS seconds
  FROM latest_contributions GROUP BY distinct_id
), members AS (
  SELECT e.distinct_id,
    JSONExtract(ifNull(tupleElement(e.answers, 1), '[]'), 'Array(String)') AS purposes,
    ifNull(t.seconds, 0) >= 7200 AS retained
  FROM entry e LEFT JOIN totals t ON e.distinct_id = t.distinct_id
), labels AS (
  SELECT distinct_id, arrayJoin(if(empty(purposes), ['unknown'], purposes)) AS purpose, retained
  FROM members
)
SELECT purpose, count() AS original_users, countIf(retained) AS retained_users,
  100.0 * countIf(retained) / count() AS retention_percent
FROM labels GROUP BY purpose ORDER BY purpose
