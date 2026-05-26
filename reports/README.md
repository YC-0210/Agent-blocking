# DO Card Weekly Reports

Auto-generated weekly analytics reports produced by the cloud routine
`do-card-weekly-report` (claude.ai/code/routines). Each `weekly-YYYY-MM-DD.md`
is a snapshot of the previous 28 days, pulled from Supabase via the
`public.get_weekly_usage_summary()` RPC.

- Cadence: every Monday 09:00 Asia/Taipei.
- Data source: `usage_daily` (anonymous, insert-only). The RPC is
  `SECURITY DEFINER` and exposes only pre-aggregated counts.
- Mirror: a local launchd job pulls this folder to
  `~/Desktop/Weekly report/` Monday 09:30 Asia/Taipei.

Do not hand-edit reports — they are reproducible by re-running the RPC.
