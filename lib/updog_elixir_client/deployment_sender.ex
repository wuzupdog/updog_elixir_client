defmodule UpdogElixirClient.DeploymentSender do
  @moduledoc """
  Sends deployment events to the Updog server.
  """

  alias UpdogElixirClient.Config

  def send_deployment(attrs) when is_map(attrs) do
    payload =
      attrs
      |> with_defaults()
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    http_client().post_json(Config.deployments_url(), payload)
  end

  defp with_defaults(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    %{
      environment: Map.get(attrs, :environment, Config.environment()),
      service: Map.get(attrs, :service),
      version: Map.get(attrs, :version, System.get_env("RELEASE_VERSION") || "unknown"),
      sha: Map.get(attrs, :sha, System.get_env("GIT_SHA")),
      deployed_at: Map.get(attrs, :deployed_at, now)
    }
  end

  defp http_client do
    Application.get_env(:updog_elixir_client, :http_client, UpdogElixirClient.Client)
  end
end
