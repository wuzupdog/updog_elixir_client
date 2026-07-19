defmodule UpdogElixirClient.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: UpdogElixirClient.Finch},
      {Task.Supervisor, name: UpdogElixirClient.DeliverySupervisor},
      UpdogElixirClient.Collector
    ]

    UpdogElixirClient.TelemetryHandler.attach()
    UpdogElixirClient.VmPoller.attach()
    :logger.add_handler(:updog, UpdogElixirClient.LoggerHandler, %{})

    opts = [strategy: :one_for_one, name: UpdogElixirClient.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def prep_stop(state) do
    _ = UpdogElixirClient.Collector.flush(5_000)
    state
  end
end
