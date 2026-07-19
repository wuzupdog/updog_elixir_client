defmodule UpdogElixirClient.CollectorTest do
  use ExUnit.Case

  import Mox

  alias UpdogElixirClient.Collector

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    Application.put_env(:updog_elixir_client, :api_key, "test-key")
    Application.put_env(:updog_elixir_client, :max_batch_records, 512)
    Application.put_env(:updog_elixir_client, :max_queue_records, 2_048)
    Application.put_env(:updog_elixir_client, :max_queue_bytes, 8_388_608)

    UpdogElixirClient.CollectorState.reset()

    on_exit(fn ->
      Application.delete_env(:updog_elixir_client, :api_key)
      Application.delete_env(:updog_elixir_client, :max_batch_records)
      Application.delete_env(:updog_elixir_client, :max_queue_records)
      Application.delete_env(:updog_elixir_client, :max_queue_bytes)
    end)

    :ok
  end

  test "capture stays in memory until a flush and preserves order" do
    Collector.push_event(%{type: "test", data: 1})
    Collector.push_event(%{type: "test", data: 2})
    state = :sys.get_state(Collector)

    assert Enum.map(state.queues.events, & &1.data.data) == [1, 2]

    expect(UpdogElixirClient.MockHttpClient, :post_json, fn url, payload ->
      assert url =~ "/api/v1/events"
      assert Enum.map(payload.events, & &1.data) == [1, 2]
      :ok
    end)

    assert :ok = Collector.flush(1_000)
    assert %{queue_records: 0, in_flight: 0, sent: 2} = Collector.stats()
  end

  test "a full queue evicts lower-priority telemetry for an error" do
    Application.put_env(:updog_elixir_client, :max_queue_records, 2)

    Collector.push_metric(%{name: "cpu", value: 1})
    Collector.push_event(%{type: "span", operation: "query"})
    Collector.push_notice(%{error_class: "RuntimeError", message: "failed"})
    state = :sys.get_state(Collector)

    assert state.queues.metrics == []
    assert length(state.queues.events) == 1
    assert length(state.queues.notices) == 1
    assert state.counters.dropped.evicted_for_priority == 1
  end

  test "an unencodable record is dropped without crashing the collector" do
    Collector.push_metric(%{name: "pid", value: self()})
    state = :sys.get_state(Collector)

    assert state.counters.dropped.encoding_error == 1
    assert state.queue_records == 0
  end

  test "a 413 splits a batch and delivers both halves" do
    Application.put_env(:updog_elixir_client, :max_batch_records, 2)

    expect(UpdogElixirClient.MockHttpClient, :post_json, 3, fn _url, payload ->
      if length(payload.logs) == 2, do: {:error, :payload_too_large}, else: :ok
    end)

    Collector.push_log(%{level: "info", message: "one"})
    Collector.push_log(%{level: "info", message: "two"})

    assert :ok = Collector.flush(1_000)
    assert %{sent: 2, dropped: dropped} = Collector.stats()
    assert dropped == %{}
  end

  test "flush honors its timeout while a delivery is still in flight" do
    expect(UpdogElixirClient.MockHttpClient, :post_json, fn _url, _payload ->
      receive do
        :complete_delivery -> :ok
      after
        500 -> :ok
      end
    end)

    Collector.push_event(%{type: "test"})
    assert {:error, :timeout} = Collector.flush(0)
  end
end
