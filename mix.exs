defmodule PintBroker.MixProject do
  use Mix.Project

  def project do
    [
      app: :pint_broker,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      description: description(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:tortoise311, "~> 0.11"}
    ]
  end

  defp description do
    "A simple, pint-sized MQTT broker that can be used for testing and development"
  end
end
