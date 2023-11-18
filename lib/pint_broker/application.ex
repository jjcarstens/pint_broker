defmodule PintBroker.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children =
      case Application.get_all_env(:pint_broker) do
        [] ->
          # No app environment, so don't start
          []

        app_env ->
          [{PintBroker, app_env}]
      end

    opts = [strategy: :one_for_one, name: PintBroker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
