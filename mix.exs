defmodule PintBroker.MixProject do
  use Mix.Project

  @version "1.0.2"
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
      name: "PintBroker 🍺",
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
      extra_applications: [:logger],
      mod: {PintBroker.Application, []}
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
      api_reference: false,
      extras: ["README.md", "CHANGELOG.md"],
      main: "readme",
      markdown_processor: __MODULE__,
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  # Used to convert GitHub alerts to ExDoc admonitions
  def to_ast(text, opts) do
    regex = ~r/> \[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/

    text =
      Regex.replace(regex, text, fn _line, gh_admon ->
        ex_admon =
          case gh_admon do
            "NOTE" <> _ -> ".neutral"
            "TIP" <> _ -> ".tip"
            "IMPORTANT" <> _ -> ".info"
            "WARNING" <> _ -> ".warning"
            "CAUTION" <> _ -> ".error"
          end

        "> #### #{String.capitalize(gh_admon)} {: #{ex_admon}}"
      end)

    ExDoc.Markdown.Earmark.to_ast(text, opts)
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
