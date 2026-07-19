defmodule UpdogElixirClient.ConfigTest do
  use ExUnit.Case

  alias UpdogElixirClient.Config

  setup do
    # Store original values
    original = %{
      api_key: Application.get_env(:updog_elixir_client, :api_key),
      endpoint: Application.get_env(:updog_elixir_client, :endpoint),
      environment: Application.get_env(:updog_elixir_client, :environment),
      sample_rate: Application.get_env(:updog_elixir_client, :sample_rate)
    }

    on_exit(fn ->
      # Restore original values
      Enum.each(original, fn {key, value} ->
        if value == nil do
          Application.delete_env(:updog_elixir_client, key)
        else
          Application.put_env(:updog_elixir_client, key, value)
        end
      end)
    end)

    :ok
  end

  describe "default values" do
    test "api_key defaults to nil" do
      Application.delete_env(:updog_elixir_client, :api_key)
      assert Config.api_key() == nil
    end

    test "endpoint defaults to production" do
      Application.delete_env(:updog_elixir_client, :endpoint)
      assert Config.endpoint() == "https://wuzupdog.com"
    end

    test "environment defaults to dev" do
      Application.delete_env(:updog_elixir_client, :environment)
      assert Config.environment() == "dev"
    end

    test "sample_rate defaults to 1.0" do
      Application.delete_env(:updog_elixir_client, :sample_rate)
      assert Config.sample_rate() == 1.0
    end

    test "ecto_repos defaults to empty list" do
      Application.delete_env(:updog_elixir_client, :ecto_repos)
      assert Config.ecto_repos() == []
    end
  end

  describe "custom values" do
    test "reads configured api_key" do
      Application.put_env(:updog_elixir_client, :api_key, "test-key-123")
      assert Config.api_key() == "test-key-123"
    end

    test "reads configured endpoint" do
      Application.put_env(:updog_elixir_client, :endpoint, "https://updog.example.com")
      assert Config.endpoint() == "https://updog.example.com"
    end

    test "reads configured environment" do
      Application.put_env(:updog_elixir_client, :environment, "production")
      assert Config.environment() == "production"
    end

    test "reads configured sample_rate" do
      Application.put_env(:updog_elixir_client, :sample_rate, 0.5)
      assert Config.sample_rate() == 0.5
    end
  end

  describe "URL construction" do
    test "notices_url uses configured endpoint" do
      Application.put_env(:updog_elixir_client, :endpoint, "https://updog.io")
      assert Config.notices_url() == "https://updog.io/api/v1/notices/bulk"
    end

    test "events_url uses configured endpoint" do
      Application.put_env(:updog_elixir_client, :endpoint, "https://updog.io")
      assert Config.events_url() == "https://updog.io/api/v1/events"
    end

    test "metrics_url uses configured endpoint" do
      Application.put_env(:updog_elixir_client, :endpoint, "https://updog.io")
      assert Config.metrics_url() == "https://updog.io/api/v1/metrics"
    end

    test "logs_url uses configured endpoint" do
      Application.put_env(:updog_elixir_client, :endpoint, "https://updog.io")
      assert Config.logs_url() == "https://updog.io/api/v1/logs"
    end

    test "uses default endpoint when not configured" do
      Application.delete_env(:updog_elixir_client, :endpoint)
      assert Config.notices_url() == "https://wuzupdog.com/api/v1/notices/bulk"
    end
  end
end
