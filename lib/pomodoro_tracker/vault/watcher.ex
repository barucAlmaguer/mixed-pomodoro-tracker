defmodule PomodoroTracker.Vault.Watcher do
  @moduledoc """
  Watches the pomodoro-tracker subdir of both vaults and broadcasts changes
  on the `"vault"` PubSub topic so LiveViews can refresh.
  """

  use GenServer
  require Logger

  @topic "vault"

  def topic, do: @topic

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    paths =
      [:work, :personal]
      |> Enum.map(&PomodoroTracker.Vault.subdir/1)
      |> Enum.filter(&File.dir?/1)

    case paths do
      [] ->
        Logger.warning("Vault.Watcher: no vault subdirs found, skipping watcher")
        :ignore

      dirs ->
        {:ok, pid} = FileSystem.start_link(dirs: dirs)
        FileSystem.subscribe(pid)
        Logger.info("Vault.Watcher: watching #{inspect(dirs)}")
        {:ok, %{pid: pid, debounce: nil}}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    if relevant?(path, events) do
      # debounce: collapse bursts into a single broadcast ~100ms later
      if state.debounce, do: Process.cancel_timer(state.debounce)
      ref = Process.send_after(self(), :flush, 100)
      {:noreply, %{state | debounce: ref}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:flush, state) do
    Phoenix.PubSub.broadcast(PomodoroTracker.PubSub, @topic, :vault_changed)
    {:noreply, %{state | debounce: nil}}
  end

  def handle_info({:file_event, _pid, :stop}, state), do: {:noreply, state}

  defp relevant?(path, _events) do
    String.ends_with?(path, ".md")
  end
end
