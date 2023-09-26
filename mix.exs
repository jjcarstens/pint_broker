defmodule PintBroker.MixProject do
  use Mix.Project

  def project do
    [
      app: :pint_broker,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      description: description(),
      deps: deps(),
      dialyzer: dialyzer(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: :dev},
      {:dialyxir, "~> 1.4", only: :dev},
      {:tortoise311, "~> 0.11"}
    ]
  end

  defp description do
    "A simple, pint-sized MQTT broker that can be used for testing and development"
  end

  defp dialyzer do
    [
      flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling, :underspecs],
      list_unused_filters: true
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"]
    ]
  end
end
