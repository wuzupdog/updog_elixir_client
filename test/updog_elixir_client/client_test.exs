defmodule UpdogElixirClient.ClientTest do
  use ExUnit.Case

  alias UpdogElixirClient.Client

  setup do
    original_key = Application.get_env(:updog_elixir_client, :api_key)

    on_exit(fn ->
      if original_key do
        Application.put_env(:updog_elixir_client, :api_key, original_key)
      else
        Application.delete_env(:updog_elixir_client, :api_key)
      end
    end)

    :ok
  end

  test "does not construct an HTTP request without an API key" do
    Application.delete_env(:updog_elixir_client, :api_key)

    assert {:error, :disabled} = Client.post_json("https://example.com/events", %{events: []})
  end
end
