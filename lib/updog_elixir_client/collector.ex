defmodule UpdogElixirClient.Collector do
  @moduledoc """
  Bounded telemetry queue with one supervised delivery task per signal.

  Capture calls only enqueue. Network retries, batching, and 413 splitting happen
  outside the caller and outside the collector process.
  """

  use GenServer

  alias UpdogElixirClient.Config

  @signals [:notices, :deployments, :logs, :events, :metrics]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def push_event(event), do: enqueue(:events, event)
  def push_log(log), do: enqueue(:logs, log)
  def push_metric(metric), do: enqueue(:metrics, metric)
  def push_notice(notice), do: enqueue(:notices, notice)
  def push_deployment(deployment), do: enqueue(:deployments, deployment)

  def flush(timeout \\ 5_000) when is_integer(timeout) and timeout >= 0 do
    GenServer.call(__MODULE__, {:flush, timeout}, timeout + 100)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def stats, do: GenServer.call(__MODULE__, :stats)

  def record_retry do
    if Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, :retried)
    :ok
  end

  defp enqueue(signal, record) when signal in @signals and is_map(record) do
    GenServer.cast(__MODULE__, {:enqueue, signal, record})
  end

  @impl true
  def init(_opts) do
    schedule_flush()

    {:ok,
     %{
       queues: Map.new(@signals, &{&1, []}),
       queue_records: 0,
       queue_bytes: 0,
       inflight: %{},
       waiters: %{},
       counters: %{queued: 0, sent: 0, retried: 0, dropped: %{}}
     }}
  end

  @impl true
  def handle_cast({:enqueue, signal, data}, state) do
    state =
      case build_record(signal, data) do
        {:error, :encoding} ->
          diagnostic("dropping record that could not be encoded")
          drop(state, :encoding_error)

        {:ok, record} ->
          if record.size > Config.max_record_bytes() do
            drop(state, :record_too_large)
          else
            state
            |> make_room(record)
            |> add_if_room(signal, record)
            |> maybe_dispatch_full(signal)
          end
      end

    {:noreply, state}
  end

  def handle_cast(:retried, state) do
    {:noreply, update_in(state.counters.retried, &(&1 + 1))}
  end

  @impl true
  def handle_call(:stats, _from, state), do: {:reply, public_stats(state), state}

  def handle_call({:flush, timeout}, from, state) do
    state = dispatch_all(state)

    if idle?(state) do
      {:reply, :ok, state}
    else
      token = make_ref()
      timer = Process.send_after(self(), {:flush_timeout, token}, timeout)
      {:noreply, put_in(state.waiters[token], {from, timer})}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    schedule_flush()
    {:noreply, dispatch_all(state)}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    case Map.pop(state.inflight, ref) do
      {nil, _inflight} ->
        {:noreply, state}

      {%{signal: signal, records: records}, inflight} ->
        Process.demonitor(ref, [:flush])

        state =
          %{state | inflight: inflight}
          |> finish_delivery(result, length(records))
          |> dispatch_signal(signal)
          |> reply_waiters_if_idle()

        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.inflight, ref) do
      {nil, _inflight} ->
        {:noreply, state}

      {%{signal: signal, records: records}, inflight} ->
        diagnostic("delivery task exited: #{inspect(reason)}")

        state =
          %{state | inflight: inflight}
          |> drop_many(:worker_crash, length(records))
          |> dispatch_signal(signal)
          |> reply_waiters_if_idle()

        {:noreply, state}
    end
  end

  def handle_info({:flush_timeout, token}, state) do
    case Map.pop(state.waiters, token) do
      {nil, _waiters} ->
        {:noreply, state}

      {{from, _timer}, waiters} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | waiters: waiters}}
    end
  end

  defp build_record(signal, data) do
    data = normalize(signal, data)

    case Jason.encode_to_iodata(data) do
      {:ok, encoded} ->
        {:ok,
         %{
           data: data,
           size: IO.iodata_length(encoded),
           priority: priority(signal, data)
         }}

      {:error, _reason} ->
        {:error, :encoding}
    end
  end

  defp normalize(signal, data) do
    data
    |> put_default(:event_id, generate_id("evt"))
    |> put_default(timestamp_key(signal), now())
    |> put_default(:service, Config.service())
    |> put_default(:environment, Config.environment())
    |> put_default(:release, Config.release())
    |> put_default(:hostname, hostname())
    |> put_default(:sdk_name, "updog_elixir_client")
    |> put_default(:sdk_version, sdk_version())
  end

  defp put_default(map, key, value) do
    if Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key)) do
      map
    else
      Map.put(map, key, value)
    end
  end

  defp timestamp_key(:notices), do: :occurred_at
  defp timestamp_key(:logs), do: :timestamp
  defp timestamp_key(:metrics), do: :recorded_at
  defp timestamp_key(:events), do: :started_at
  defp timestamp_key(:deployments), do: :deployed_at

  defp priority(:notices, _), do: 100
  defp priority(:deployments, _), do: 90
  defp priority(:logs, data), do: log_priority(Map.get(data, :level, Map.get(data, "level")))
  defp priority(:events, _), do: 20
  defp priority(:metrics, _), do: 10

  defp log_priority(level) when level in [:emergency, :alert, :critical, :error], do: 80
  defp log_priority(level) when level in ["emergency", "alert", "critical", "error"], do: 80
  defp log_priority(level) when level in [:warning, :warn, "warning", "warn"], do: 50
  defp log_priority(_), do: 30

  defp make_room(state, record) do
    if room?(state, record) do
      state
    else
      case eviction_candidate(state, record.priority) do
        nil -> state
        signal -> state |> evict_head(signal) |> make_room(record)
      end
    end
  end

  defp room?(state, record) do
    state.queue_records < Config.max_queue_records() and
      state.queue_bytes + record.size <= Config.max_queue_bytes()
  end

  defp eviction_candidate(state, incoming_priority) do
    state.queues
    |> Enum.flat_map(fn {signal, records} ->
      records
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {%{priority: priority}, index} when priority < incoming_priority ->
          [{signal, index, priority}]

        _ ->
          []
      end)
    end)
    |> Enum.min_by(&elem(&1, 2), fn -> nil end)
    |> case do
      nil -> nil
      {signal, index, _priority} -> {signal, index}
    end
  end

  defp evict_head(state, {signal, index}) do
    {record, rest} = List.pop_at(state.queues[signal], index)

    state
    |> put_in([:queues, signal], rest)
    |> Map.update!(:queue_records, &(&1 - 1))
    |> Map.update!(:queue_bytes, &(&1 - record.size))
    |> drop(:evicted_for_priority)
  end

  defp add_if_room(state, signal, record) do
    if room?(state, record) do
      state
      |> update_in([:queues, signal], &(&1 ++ [record]))
      |> Map.update!(:queue_records, &(&1 + 1))
      |> Map.update!(:queue_bytes, &(&1 + record.size))
      |> update_in([:counters, :queued], &(&1 + 1))
    else
      drop(state, :queue_full)
    end
  end

  defp maybe_dispatch_full(state, signal) do
    records = state.queues[signal]

    if length(records) >= batch_record_limit(signal) or
         Enum.sum(Enum.map(records, & &1.size)) >= Config.max_batch_bytes() do
      dispatch_signal(state, signal)
    else
      state
    end
  end

  defp dispatch_all(state), do: Enum.reduce(@signals, state, &dispatch_signal(&2, &1))

  defp dispatch_signal(state, signal) do
    if inflight_signal?(state, signal) do
      state
    else
      {records, rest} =
        take_batch(
          state.queues[signal],
          batch_record_limit(signal),
          Config.max_batch_bytes(),
          envelope_overhead(signal)
        )

      case records do
        [] ->
          state

        _ ->
          removed_bytes = Enum.sum(Enum.map(records, & &1.size))

          task =
            Task.Supervisor.async_nolink(UpdogElixirClient.DeliverySupervisor, fn ->
              deliver(signal, records)
            end)

          state
          |> put_in([:queues, signal], rest)
          |> Map.update!(:queue_records, &(&1 - length(records)))
          |> Map.update!(:queue_bytes, &(&1 - removed_bytes))
          |> put_in([:inflight, task.ref], %{signal: signal, records: records})
      end
    end
  end

  defp take_batch(records, limit, max_bytes, overhead),
    do: take_batch(records, limit, max_bytes, [], overhead)

  defp take_batch([record | rest], limit, max_bytes, selected, bytes)
       when length(selected) < limit and
              (selected == [] or bytes + record.size + 1 <= max_bytes) do
    separator = if selected == [], do: 0, else: 1
    take_batch(rest, limit, max_bytes, [record | selected], bytes + record.size + separator)
  end

  defp take_batch(rest, _limit, _max_bytes, selected, _bytes), do: {Enum.reverse(selected), rest}

  defp deliver(signal, records) do
    payload = envelope(signal, Enum.map(records, & &1.data))

    case http_client().post_json(url(signal), payload) do
      :ok ->
        :ok

      {:error, :payload_too_large} when length(records) > 1 ->
        {left, right} = Enum.split(records, div(length(records), 2))

        with :ok <- deliver(signal, left),
             :ok <- deliver(signal, right) do
          :ok
        end

      {:error, :payload_too_large} ->
        {:error, :record_too_large}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp envelope(:events, records), do: %{events: records}
  defp envelope(:logs, records), do: %{logs: records}
  defp envelope(:metrics, records), do: %{metrics: records}
  defp envelope(:notices, records), do: %{notices: records}
  defp envelope(:deployments, [record]), do: record

  defp envelope_overhead(:deployments), do: 0
  defp envelope_overhead(_signal), do: 20

  defp url(:events), do: Config.events_url()
  defp url(:logs), do: Config.logs_url()
  defp url(:metrics), do: Config.metrics_url()
  defp url(:notices), do: Config.notices_url()
  defp url(:deployments), do: Config.deployments_url()

  defp batch_record_limit(:deployments), do: 1
  defp batch_record_limit(_signal), do: Config.max_batch_records()

  defp finish_delivery(state, :ok, count) do
    update_in(state.counters.sent, &(&1 + count))
  end

  defp finish_delivery(state, {:error, reason}, count) do
    diagnostic("dropping #{count} record(s): #{inspect(reason)}")
    drop_many(state, reason, count)
  end

  defp finish_delivery(state, other, count) do
    diagnostic("unexpected delivery result: #{inspect(other)}")
    drop_many(state, :unexpected_result, count)
  end

  defp inflight_signal?(state, signal),
    do: Enum.any?(state.inflight, fn {_ref, item} -> item.signal == signal end)

  defp idle?(state), do: state.queue_records == 0 and map_size(state.inflight) == 0

  defp reply_waiters_if_idle(state) do
    if idle?(state) do
      Enum.each(state.waiters, fn {_token, {from, timer}} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, :ok)
      end)

      %{state | waiters: %{}}
    else
      state
    end
  end

  defp drop(state, reason), do: drop_many(state, reason, 1)

  defp drop_many(state, reason, count) do
    update_in(
      state.counters.dropped,
      &Map.update(&1, reason, count, fn value -> value + count end)
    )
  end

  defp public_stats(state) do
    Map.merge(state.counters, %{
      queue_records: state.queue_records,
      queue_bytes: state.queue_bytes,
      in_flight: Enum.sum(Enum.map(state.inflight, fn {_ref, item} -> length(item.records) end))
    })
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, Config.flush_interval())
  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> ""
    end
  end

  defp sdk_version do
    case Application.spec(:updog_elixir_client, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end

  defp generate_id(prefix) do
    suffix = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    "#{prefix}_#{suffix}"
  end

  defp http_client do
    Application.get_env(:updog_elixir_client, :http_client, UpdogElixirClient.Client)
  end

  defp diagnostic(message) do
    require Logger
    Logger.warning("[UpdogElixirClient] #{message}", updog_internal: true)
  end
end
