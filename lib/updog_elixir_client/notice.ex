defmodule UpdogElixirClient.Notice do
  @moduledoc """
  Builds error notice payloads for the Updog API.
  """

  alias UpdogElixirClient.{Backtrace, Config, Context, Breadcrumbs}

  def build(exception, opts \\ []) when is_exception(exception) do
    stacktrace = Keyword.get(opts, :stacktrace, [])
    formatted_trace = Backtrace.format(stacktrace)

    %{
      error_class: inspect(exception.__struct__),
      message: Exception.message(exception),
      stacktrace: formatted_trace,
      breadcrumbs: Breadcrumbs.get(),
      context: Context.get(),
      request: Keyword.get(opts, :request, %{}),
      environment: Config.environment(),
      hostname: hostname(),
      fingerprint: Keyword.get(opts, :fingerprint),
      service: Config.service(),
      release: Config.release(),
      handled: Keyword.get(opts, :handled, true),
      mechanism: Keyword.get(opts, :mechanism, "exception"),
      occurred_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def build_from_error(kind, reason, stacktrace, opts \\ []) do
    formatted_trace = Backtrace.format(stacktrace)
    error_class = format_error_class(kind, reason)
    message = format_error_message(kind, reason)

    %{
      error_class: error_class,
      message: message,
      stacktrace: formatted_trace,
      breadcrumbs: Breadcrumbs.get(),
      context: Context.get(),
      request: Keyword.get(opts, :request, %{}),
      environment: Config.environment(),
      hostname: hostname(),
      fingerprint: Keyword.get(opts, :fingerprint),
      service: Config.service(),
      release: Config.release(),
      handled: Keyword.get(opts, :handled, true),
      mechanism: Keyword.get(opts, :mechanism, to_string(kind)),
      occurred_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp format_error_class(:error, %{__struct__: mod}), do: inspect(mod)
  defp format_error_class(:error, reason), do: inspect(reason)
  defp format_error_class(kind, _reason), do: to_string(kind)

  defp format_error_message(:error, reason) when is_exception(reason) do
    Exception.message(reason)
  end

  defp format_error_message(_kind, reason), do: inspect(reason)

  defp hostname do
    {:ok, name} = :inet.gethostname()
    to_string(name)
  end
end
