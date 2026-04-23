defmodule PomodoroTracker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PomodoroTrackerWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:pomodoro_tracker, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PomodoroTracker.PubSub},
      PomodoroTracker.Timer,
      PomodoroTracker.Vault.Watcher,
      PomodoroTrackerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PomodoroTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PomodoroTrackerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
