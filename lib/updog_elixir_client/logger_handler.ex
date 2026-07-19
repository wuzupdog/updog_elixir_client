defmodule UpdogElixirClient.LoggerHandler do
  @moduledoc """
  Erlang :logger handler that captures log entries and crash reports.

  - All log entries are pushed to the Collector for batched sending as logs.
  - Crash reports (error/critical/alert/emergency) are also sent as error notices.

  Automatically installed at application start.
  """

  @behaviour :logger_handler

  alias UpdogElixirClient.Collector

  @impl true
  def log(%{meta: %{updog_internal: true}}, _config), do: :ok

  @impl true
  def log(%{level: level, msg: msg, meta: meta}, _config) do
    message = format_message(msg)

    # Push all log entries to the log collector
    Collector.push_log(%{
      level: to_string(level),
      message: message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      metadata: extract_metadata(meta),
      trace_id: metadata_value(meta, :trace_id),
      span_id: metadata_value(meta, :span_id)
    })

    # Also send crash reports as error notices
    if level in [:error, :critical, :alert, :emergency] do
      notify_crash(msg)
    end
  end

  defp notify_crash(msg) do
    case msg do
      {:report, %{reason: {exception, stacktrace}}} when is_exception(exception) ->
        UpdogElixirClient.notify(exception, stacktrace: stacktrace)

      {:report, %{reason: {{kind, reason}, stacktrace}}} when is_list(stacktrace) ->
        UpdogElixirClient.notify_error(kind, reason, stacktrace)

      _ ->
        :ok
    end
  end

  defp format_message({:string, message}), do: to_string(message)
  defp format_message({:report, report}), do: inspect(report)

  defp format_message({format, args}) when is_list(args),
    do: :io_lib.format(format, args) |> to_string()

  defp format_message(other), do: inspect(other)

  defp extract_metadata(meta) do
    meta
    |> Map.take([:module, :function, :file, :line, :domain, :pid])
    |> Map.new(fn {k, v} -> {k, inspect(v)} end)
  end

  defp metadata_value(meta, key), do: meta |> Map.get(key, "") |> to_string()

  @impl true
  def adding_handler(config), do: {:ok, config}

  @impl true
  def removing_handler(_config), do: :ok

  @impl true
  def changing_config(_action, _old_config, new_config), do: {:ok, new_config}
end
