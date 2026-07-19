defmodule UpdogElixirClient.TelemetryHandler do
  @moduledoc """
  Attaches to Phoenix, Ecto, and Oban telemetry events.
  Forwards processed events to the Collector for batched sending.
  """

  alias UpdogElixirClient.{Collector, Config}

  require Logger

  def attach do
    :telemetry.attach(
      "updog-phoenix-endpoint",
      [:phoenix, :endpoint, :stop],
      &__MODULE__.handle_phoenix_event/4,
      nil
    )

    :telemetry.attach_many(
      "updog-phoenix-live-view",
      [
        [:phoenix, :live_view, :mount, :stop],
        [:phoenix, :live_view, :handle_event, :stop]
      ],
      &__MODULE__.handle_phoenix_event/4,
      nil
    )

    ecto_repos = Config.ecto_repos()

    Enum.each(ecto_repos, fn repo_path ->
      event = repo_path ++ [:query]
      id = "updog-ecto-#{Enum.join(repo_path, "-")}"
      :telemetry.attach(id, event, &__MODULE__.handle_ecto_event/4, nil)
    end)

    :telemetry.attach(
      "updog-oban",
      [:oban, :job, :stop],
      &__MODULE__.handle_oban_event/4,
      nil
    )
  end

  def handle_phoenix_event([:phoenix, :endpoint, :stop], measurements, metadata, _config) do
    try do
      trace_id = trace_id(metadata)

      if should_sample?(trace_id) do
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

        Collector.push_event(%{
          type: "trace",
          trace_id: trace_id,
          span_id: span_id(metadata),
          transaction_name: "#{metadata.conn.method} #{metadata.conn.request_path}",
          trace_type: "http",
          duration_ms: duration_ms,
          status_code: metadata.conn.status,
          method: metadata.conn.method,
          path: metadata.conn.request_path,
          started_at: started_at(duration_ms)
        })
      end
    rescue
      e ->
        Logger.warning("Updog endpoint telemetry handler error: #{inspect(e)}",
          updog_internal: true
        )
    end
  end

  def handle_phoenix_event([:phoenix, :live_view | _], measurements, metadata, _config) do
    try do
      trace_id = trace_id(metadata)

      if should_sample?(trace_id) do
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
        view = metadata[:socket] && metadata[:socket].view

        Collector.push_event(%{
          type: "span",
          trace_id: trace_id,
          parent_span_id: parent_span_id(metadata),
          span_id: span_id(metadata),
          operation: "live_view",
          description: inspect(view || "unknown"),
          duration_ms: duration_ms,
          started_at: started_at(duration_ms)
        })
      end
    rescue
      e ->
        Logger.warning("Updog live_view telemetry handler error: #{inspect(e)}",
          updog_internal: true
        )
    end
  end

  def handle_phoenix_event(_, _, _, _), do: :ok

  def handle_ecto_event(_event, measurements, metadata, _config) do
    try do
      trace_id = trace_id(metadata)

      if should_sample?(trace_id) do
        duration_ms =
          System.convert_time_unit(measurements.total_time || 0, :native, :millisecond)

        Collector.push_event(%{
          type: "span",
          trace_id: trace_id,
          parent_span_id: parent_span_id(metadata),
          span_id: span_id(metadata),
          operation: "ecto.query",
          description: metadata[:source] || "unknown",
          duration_ms: duration_ms,
          started_at: started_at(duration_ms)
        })
      end
    rescue
      e ->
        Logger.warning("Updog ecto telemetry handler error: #{inspect(e)}", updog_internal: true)
    end
  end

  def handle_oban_event(_event, measurements, metadata, _config) do
    try do
      trace_id = trace_id(metadata)

      if should_sample?(trace_id) do
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

        Collector.push_event(%{
          type: "span",
          trace_id: trace_id,
          parent_span_id: parent_span_id(metadata),
          span_id: span_id(metadata),
          operation: "oban.job",
          description: inspect(metadata[:worker]),
          duration_ms: duration_ms,
          started_at: started_at(duration_ms)
        })
      end
    rescue
      e ->
        Logger.warning("Updog oban telemetry handler error: #{inspect(e)}", updog_internal: true)
    end
  end

  defp should_sample?(trace_id) do
    case Config.sample_rate() do
      rate when rate <= 0 ->
        false

      rate when rate >= 1 ->
        true

      rate ->
        threshold = trunc(rate * 4_294_967_295)
        <<value::unsigned-32, _::binary>> = :crypto.hash(:sha256, to_string(trace_id))
        value <= threshold
    end
  end

  defp trace_id(metadata), do: to_string(metadata[:trace_id] || generate_trace_id())
  defp span_id(metadata), do: to_string(metadata[:span_id] || generate_span_id())
  defp parent_span_id(metadata), do: to_string(metadata[:parent_span_id] || "")

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.hex_encode32(case: :lower, padding: false)
  end

  defp generate_span_id do
    :crypto.strong_rand_bytes(8) |> Base.hex_encode32(case: :lower, padding: false)
  end

  defp started_at(duration_ms) do
    DateTime.utc_now()
    |> DateTime.add(-duration_ms, :millisecond)
    |> DateTime.to_iso8601()
  end
end
