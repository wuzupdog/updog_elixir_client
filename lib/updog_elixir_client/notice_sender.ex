defmodule UpdogElixirClient.NoticeSender do
  @moduledoc """
  Sends error notices immediately to the Updog server.
  """

  alias UpdogElixirClient.{Collector, Notice}

  def send_notice(exception, opts \\ []) do
    payload = Notice.build(exception, opts)
    Collector.push_notice(payload)
  end

  def send_error(kind, reason, stacktrace, opts \\ []) do
    payload = Notice.build_from_error(kind, reason, stacktrace, opts)
    Collector.push_notice(payload)
  end
end
