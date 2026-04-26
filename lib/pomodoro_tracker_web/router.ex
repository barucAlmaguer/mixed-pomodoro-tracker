defmodule PomodoroTrackerWeb.Router do
  use PomodoroTrackerWeb, :router

  pipeline :browser do
    plug PomodoroTrackerWeb.Plugs.ManifestRedirect
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PomodoroTrackerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PomodoroTrackerWeb do
    pipe_through :browser

    live "/", DayLive, :index
    live "/floating", FloatingLive, :index
    live "/planner", RecurrentPlannerLive, :index
  end

  scope "/api", PomodoroTrackerWeb do
    pipe_through :api

    get "/state", StateController, :show
  end
end
