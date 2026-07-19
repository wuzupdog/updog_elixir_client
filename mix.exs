defmodule UpdogElixirClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :updog_elixir_client,
      version: "0.2.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Client library for the Updog APM platform",
      package: package()
    ]
  end

  def application do
    [
      mod: {UpdogElixirClient.Application, []},
      extra_applications: [:logger, :inets]
    ]
  end

  defp deps do
    [
      {:finch, "~> 0.18"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:plug, "~> 1.14", optional: true},
      {:mox, "~> 1.0", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{}
    ]
  end
end
