defmodule UpdogElixirClient.Config do
  @moduledoc """
  Configuration reader with defaults.
  """

  def api_key, do: Application.get_env(:updog_elixir_client, :api_key)

  def enabled? do
    case api_key() do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end

  def endpoint, do: Application.get_env(:updog_elixir_client, :endpoint, "https://wuzupdog.com")
  def environment, do: Application.get_env(:updog_elixir_client, :environment, "dev")
  def sample_rate, do: Application.get_env(:updog_elixir_client, :sample_rate, 1.0)
  def ecto_repos, do: Application.get_env(:updog_elixir_client, :ecto_repos, [])
  def service, do: Application.get_env(:updog_elixir_client, :service, "")
  def release, do: Application.get_env(:updog_elixir_client, :release, "")
  def flush_interval, do: Application.get_env(:updog_elixir_client, :flush_interval, 5_000)
  def max_queue_records, do: Application.get_env(:updog_elixir_client, :max_queue_records, 2_048)
  def max_queue_bytes, do: Application.get_env(:updog_elixir_client, :max_queue_bytes, 8_388_608)
  def max_record_bytes, do: Application.get_env(:updog_elixir_client, :max_record_bytes, 65_536)
  def max_batch_records, do: Application.get_env(:updog_elixir_client, :max_batch_records, 512)
  def max_batch_bytes, do: Application.get_env(:updog_elixir_client, :max_batch_bytes, 524_288)
  def request_timeout, do: Application.get_env(:updog_elixir_client, :request_timeout, 5_000)
  def max_retries, do: Application.get_env(:updog_elixir_client, :max_retries, 3)

  def notices_url, do: "#{endpoint()}/api/v1/notices/bulk"
  def events_url, do: "#{endpoint()}/api/v1/events"
  def metrics_url, do: "#{endpoint()}/api/v1/metrics"
  def logs_url, do: "#{endpoint()}/api/v1/logs"
  def deployments_url, do: "#{endpoint()}/api/v1/deployments"
end
