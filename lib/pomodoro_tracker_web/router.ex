defmodule PomodoroTrackerWeb.Router do
  use PomodoroTrackerWeb, :router

  pipeline :browser do
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
  end

  # Other scopes may use custom stacks.
  # scope "/api", PomodoroTrackerWeb do
  #   pipe_through :api
  # end
end
