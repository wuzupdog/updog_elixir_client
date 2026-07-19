defmodule UpdogElixirClient.CollectorState do
  @moduledoc false

  def reset do
    :sys.replace_state(UpdogElixirClient.Collector, fn _state ->
      %{
        queues: Map.new([:notices, :deployments, :logs, :events, :metrics], &{&1, []}),
        queue_records: 0,
        queue_bytes: 0,
        inflight: %{},
        waiters: %{},
        counters: %{queued: 0, sent: 0, retried: 0, dropped: %{}}
      }
    end)
  end
end
