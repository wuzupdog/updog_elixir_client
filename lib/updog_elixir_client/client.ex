defmodule UpdogElixirClient.Client do
  @moduledoc """
  Synchronous HTTP transport used only by the supervised delivery worker.
  Public capture calls never invoke this module directly.
  """

  @behaviour UpdogElixirClient.HttpClient

  require Logger

  alias UpdogElixirClient.Config

  @impl true
  def post(url, body) when is_binary(body) do
    request_id = generate_id("req")
    deliver(url, body, request_id, 0)
  end

  @impl true
  def post_json(url, data) do
    case Jason.encode(data) do
      {:ok, body} ->
        post(url, body)

      {:error, reason} ->
        Logger.warning("[UpdogElixirClient] JSON encode failed: #{inspect(reason)}",
          updog_internal: true
        )

        {:error, :encoding}
    end
  end

  defp deliver(url, body, request_id, attempt) do
    headers = [
      {"content-type", "application/json"},
      {"x-api-key", Config.api_key()},
      {"x-updog-request-id", request_id}
    ]

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, UpdogElixirClient.Finch,
           receive_timeout: Config.request_timeout()
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: 413}} ->
        {:error, :payload_too_large}

      {:ok, %{status: status} = response} when status in [408, 429] or status >= 500 ->
        retry(url, body, request_id, attempt, retry_after(response.headers))

      {:ok, %{status: status}} ->
        diagnostic("POST #{url} returned permanent status #{status}")
        {:error, {:permanent, status}}

      {:error, reason} ->
        retry(url, body, request_id, attempt, nil, reason)
    end
  end

  defp retry(url, body, request_id, attempt, retry_after_ms, reason \\ nil) do
    if attempt < Config.max_retries() do
      UpdogElixirClient.Collector.record_retry()
      backoff = retry_after_ms || full_jitter(attempt)
      Process.sleep(backoff)
      deliver(url, body, request_id, attempt + 1)
    else
      diagnostic("POST #{url} exhausted retries: #{inspect(reason || :retryable_status)}")
      {:error, :retries_exhausted}
    end
  end

  defp retry_after(headers) do
    headers
    |> Enum.find_value(fn
      {name, value} when name in ["retry-after", "Retry-After"] -> value
      _ -> nil
    end)
    |> case do
      nil ->
        nil

      value ->
        retry_after_value(value)
    end
  end

  defp retry_after_value(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 ->
        min(seconds * 1_000, 30_000)

      _ ->
        case apply(:httpd_util, :convert_request_date, [String.to_charlist(value)]) do
          {{year, month, day}, {hour, minute, second}} ->
            retry_at = DateTime.new!(Date.new!(year, month, day), Time.new!(hour, minute, second))

            retry_at
            |> DateTime.diff(DateTime.utc_now(), :millisecond)
            |> max(0)
            |> min(30_000)

          _ ->
            nil
        end
    end
  rescue
    _error -> nil
  end

  defp full_jitter(attempt) do
    ceiling = min(trunc(:math.pow(2, attempt) * 250), 30_000)
    :rand.uniform(ceiling + 1) - 1
  end

  defp generate_id(prefix) do
    suffix = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    "#{prefix}_#{suffix}"
  end

  defp diagnostic(message),
    do: Logger.warning("[UpdogElixirClient] #{message}", updog_internal: true)
end
