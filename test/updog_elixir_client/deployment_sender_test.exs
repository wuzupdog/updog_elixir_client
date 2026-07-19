defmodule UpdogElixirClient.DeploymentSenderTest do
  use ExUnit.Case

  import Mox

  alias UpdogElixirClient.DeploymentSender

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    Application.put_env(:updog_elixir_client, :api_key, "test-key")
    UpdogElixirClient.CollectorState.reset()

    on_exit(fn -> Application.delete_env(:updog_elixir_client, :api_key) end)

    :ok
  end

  test "send_deployment/1 posts deployments payload" do
    expect(UpdogElixirClient.MockHttpClient, :post_json, fn url, payload ->
      assert url =~ "/api/v1/deployments"
      assert payload.environment == "production"
      assert payload.service == "api"
      assert payload.version == "v1.2.3"
      assert payload.sha == "abc123"
      assert payload.deployed_at
      :ok
    end)

    DeploymentSender.send_deployment(%{
      environment: "production",
      service: "api",
      version: "v1.2.3",
      sha: "abc123"
    })

    assert :ok = UpdogElixirClient.flush(1_000)
  end
end
