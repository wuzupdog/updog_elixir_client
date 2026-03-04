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
  sample_rate: 1.0,
  ecto_repos: [[:my_app, :repo]]
```

| Option | Default | Description |
|--------|---------|-------------|
| `api_key` | required | Your Updog project API key |
| `endpoint` | `https://wuzupdog.com` | Updog server URL |
| `environment` | `"dev"` | Environment name (e.g. `"production"`) |
| `sample_rate` | `1.0` | Trace sampling rate (`0.0` to `1.0`) |
| `ecto_repos` | `[]` | List of telemetry event prefixes for your Ecto repos |

## Integration

### 1. Add the Plug to your endpoint

```elixir
# lib/my_app_web/endpoint.ex
plug UpdogElixirClient.Plug
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
