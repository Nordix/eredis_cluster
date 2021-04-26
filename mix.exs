defmodule EredisCluster.Mixfile do
  use Mix.Project

  @source_url "https://github.com/Nordix/eredis_cluster/"
  @version String.trim(File.read!("VERSION"))

  def project do
    [
      app: :eredis_cluster,
      deps: deps(),
      description: "An erlang wrapper for eredis library to support cluster mode",
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md", "doc/eredis_cluster.md", "doc/eredis_cluster_monitor.md"],
        api_reference: false
      ],
      elixir: ">= 1.5.1",
      package: package(),
      source_url: @source_url,
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end

  def application do
    [
      mod: {:eredis_cluster, []},
      applications: [:eredis, :poolboy]
    ]
  end

  defp deps do
    [
      {:poolboy, "1.5.2"},
      {:eredis, "~> 1.3.3"},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ["src", "include", "mix.exs", "rebar.config", "README.md",
              "CHANGELOG.md", "LICENSE", "VERSION"],
      maintainers: ["Viktor Söderqvist", "Björn Svensson"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
