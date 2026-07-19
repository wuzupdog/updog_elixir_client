# Changelog

## 0.2.0

- Make public capture calls non-blocking through a bounded supervised in-memory queue.
- Bulk errors, traces, logs, and metrics with stable event/request IDs and resource metadata.
- Add retry classification, `Retry-After`, full-jitter backoff, 413 splitting, delivery counters, and bounded `flush/1`.
- Preserve trace/span relationships when instrumentation metadata supplies them and use one deterministic sampling decision per trace.
