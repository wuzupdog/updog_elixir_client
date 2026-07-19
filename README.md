# updog_elixir_client

Elixir client for [Updog](https://wuzupdog.com) — lightweight application monitoring with traces, spans, logs, and error tracking.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:updog_elixir_client, git: "https://github.com/your-org/updog_elixir_client.git"}
  ]
end
```

## Configuration

```elixir
# config/config.exs
config :updog_elixir_client,
  api_key: System.get_env("UPDOG_API_KEY"),
  endpoint: "https://wuzupdog.com",
  environment: "production",
  service: "checkout-api",
  release: System.get_env("RELEASE_VERSION"),
  sample_rate: 1.0,
  ecto_repos: [[:my_app, :repo]]
```

| Option | Default | Description |
|--------|---------|-------------|
| `api_key` | required | Your Updog project API key |
| `endpoint` | `https://wuzupdog.com` | Updog server URL |
| `environment` | `"dev"` | Environment name (e.g. `"production"`) |
| `service` | `""` | Logical service name attached to every record |
| `release` | `""` | Release/version attached to every record |
| `sample_rate` | `1.0` | Trace sampling rate (`0.0` to `1.0`) |
| `ecto_repos` | `[]` | List of telemetry event prefixes for your Ecto repos |

## Delivery guarantees and limits

Capture calls are fire-and-forget from the application’s perspective: they enqueue into one bounded, supervised in-memory collector and never perform HTTP on the caller. The collector batches up to 512 records or 512 KiB every five seconds, with defaults of 2,048 records, 8 MiB total queue memory, and 64 KiB per record. Errors can evict lower-priority metrics, traces, or routine logs when the queue is full.

The worker retries network failures, `408`, `429`, and `5xx` three times with full-jitter exponential backoff and honors `Retry-After`. Permanent client errors are dropped, while `413` batches are split. Stable event and request IDs make retries idempotent. No disk spool is enabled by default.

For short-lived jobs and orderly shutdowns, call:

```elixir
UpdogElixirClient.flush(5_000)
UpdogElixirClient.delivery_stats()
```

The application callback performs a bounded five-second flush before the supervision tree stops.

## Integration

### 1. Add the error handler to your endpoint

```elixir
# lib/my_app_web/endpoint.ex
use UpdogElixirClient.Plug
```

### 2. Telemetry auto-attaches on startup

The client automatically attaches to:

- **Phoenix endpoint** — HTTP request traces (`type: "trace"`)
- **Phoenix LiveView** — mount and handle_event spans
- **Ecto** — database query spans
- **Oban** — background job spans

### 3. Log forwarding

```elixir
# config/config.exs
config :logger,
  backends: [:console, UpdogElixirClient.LoggerBackend]
```

## What gets tracked

| Event | Type | Description |
|-------|------|-------------|
| HTTP requests | `trace` | Method, path, status code, duration |
| LiveView events | `span` | Mount and handle_event with view module |
| Ecto queries | `span` | Query source table and duration |
| Oban jobs | `span` | Worker module and duration |
| Logs | `log` | All logger output at configured level |
| Errors | `error` | Exceptions with stacktraces |

## Deployment tracking

You can publish deployment markers to help correlate regressions with releases:

```elixir
UpdogElixirClient.notify_deployment(%{
  environment: "production",
  service: "api",
  version: "v1.2.3",
  sha: "abc123"
})
```
