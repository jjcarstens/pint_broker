defmodule PintBroker.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/jjcarstens/pint_broker"

  def project do
    [
      app: :pint_broker,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      description: description(),
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      package: package(),
      preferred_cli_env: %{
        docs: :docs,
        "hex.publish": :docs,
        "hex.build": :docs
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.30", only: :docs, runtime: false},
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

  defp docs do
    [
      extras: ["README.md", "CHANGELOG.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Github" => @source_url
      }
    ]
  end
end
