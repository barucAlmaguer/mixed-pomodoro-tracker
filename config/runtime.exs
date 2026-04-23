import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/pomodoro_tracker start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :pomodoro_tracker, PomodoroTrackerWeb.Endpoint, server: true
end

config :pomodoro_tracker, PomodoroTrackerWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT", "4123"))
  ]

# Point these at your Obsidian vaults (or any directory you want tasks to
# live in). Defaults keep everything inside the project so the app boots
# without extra setup; override via env for real vaults.
work_vault =
  System.get_env("WORK_VAULT_PATH") ||
    Path.expand("vaults/work", File.cwd!())

personal_vault =
  System.get_env("PERSONAL_VAULT_PATH") ||
    Path.expand("vaults/personal", File.cwd!())

config :pomodoro_tracker, :vaults,
  work: Path.expand(work_vault),
  personal: Path.expand(personal_vault),
  subdir: "pomodoro-tracker"

config :pomodoro_tracker, :work_hours,
  start: String.to_integer(System.get_env("WORK_START_HOUR", "9")),
  stop: String.to_integer(System.get_env("WORK_STOP_HOUR", "18")),
  weekdays: [1, 2, 3, 4, 5]

config :pomodoro_tracker, :pomodoro,
  work_minutes: String.to_integer(System.get_env("POMO_WORK_MIN", "25")),
  break_minutes: String.to_integer(System.get_env("POMO_BREAK_MIN", "5")),
  long_break_minutes: String.to_integer(System.get_env("POMO_LONG_BREAK_MIN", "15")),
  long_break_every: 4

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  port = String.to_integer(System.get_env("PORT", "4123"))
  host = System.get_env("PHX_HOST") || "localhost"

  config :pomodoro_tracker, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :pomodoro_tracker, PomodoroTrackerWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :pomodoro_tracker, PomodoroTrackerWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :pomodoro_tracker, PomodoroTrackerWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
