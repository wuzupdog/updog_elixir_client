defmodule UpdogElixirClient.Config do
  @moduledoc """
  Configuration reader with defaults.
  """

  def api_key, do: Application.get_env(:updog_elixir_client, :api_key)
  def endpoint, do: Application.get_env(:updog_elixir_client, :endpoint, "https://wuzupdog.com")
  def environment, do: Application.get_env(:updog_elixir_client, :environment, "dev")
  def sample_rate, do: Application.get_env(:updog_elixir_client, :sample_rate, 1.0)
  def ecto_repos, do: Application.get_env(:updog_elixir_client, :ecto_repos, [])

  def notices_url, do: "#{endpoint()}/api/v1/notices"
  def events_url, do: "#{endpoint()}/api/v1/events"
  def metrics_url, do: "#{endpoint()}/api/v1/metrics"
  def logs_url, do: "#{endpoint()}/api/v1/logs"
  def deployments_url, do: "#{endpoint()}/api/v1/deployments"
end
