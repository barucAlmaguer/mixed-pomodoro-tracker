defmodule PomodoroTrackerWeb.Plugs.ManifestRedirect do
  @moduledoc """
  Intercepts requests for fingerprinted manifest files (manifest-*.webmanifest)
  and serves the current manifest.webmanifest instead. This prevents 404s when
  the asset fingerprint changes but service workers still request old URLs.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if Regex.match?(~r|^/manifest-[a-f0-9]+\.webmanifest$|, conn.request_path) do
      # Serve the current manifest instead of 404
      manifest_path = Path.join(:code.priv_dir(:pomodoro_tracker), "static/manifest.webmanifest")

      case File.read(manifest_path) do
        {:ok, content} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/manifest+json")
          |> Plug.Conn.send_resp(200, content)
          |> Plug.Conn.halt()

        {:error, _} ->
          conn
      end
    else
      conn
    end
  end
end
