defmodule UpdogElixirClient.NoticeSenderTest do
  use ExUnit.Case

  import Mox

  alias UpdogElixirClient.NoticeSender

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    Application.put_env(:updog_elixir_client, :api_key, "test-key")
    UpdogElixirClient.CollectorState.reset()

    on_exit(fn -> Application.delete_env(:updog_elixir_client, :api_key) end)

    :ok
  end

  describe "send_notice/2" do
    test "sends notice payload via http_client" do
      expect(UpdogElixirClient.MockHttpClient, :post_json, fn url, payload ->
        assert url =~ "/api/v1/notices/bulk"
        assert [notice] = payload.notices
        assert notice.error_class == "RuntimeError"
        assert notice.message == "test error"
        assert notice.event_id
        assert notice.occurred_at
        :ok
      end)

      exception = %RuntimeError{message: "test error"}
      NoticeSender.send_notice(exception)
      assert :ok = UpdogElixirClient.flush(1_000)
    end

    test "includes stacktrace in payload" do
      stacktrace = [
        {MyApp.Module, :function, 2, [file: ~c"lib/my_app.ex", line: 42]}
      ]

      expect(UpdogElixirClient.MockHttpClient, :post_json, fn _url, payload ->
        assert [notice] = payload.notices
        assert length(notice.stacktrace) == 1
        assert hd(notice.stacktrace)["file"] == "lib/my_app.ex"
        :ok
      end)

      exception = %RuntimeError{message: "test"}
      NoticeSender.send_notice(exception, stacktrace: stacktrace)
      assert :ok = UpdogElixirClient.flush(1_000)
    end
  end

  describe "send_error/4" do
    test "sends error payload via http_client" do
      expect(UpdogElixirClient.MockHttpClient, :post_json, fn url, payload ->
        assert url =~ "/api/v1/notices/bulk"
        assert [notice] = payload.notices
        assert notice.error_class == "RuntimeError"
        assert notice.message == "boom"
        :ok
      end)

      NoticeSender.send_error(:error, %RuntimeError{message: "boom"}, [])
      assert :ok = UpdogElixirClient.flush(1_000)
    end
  end
end
