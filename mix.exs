defmodule Wamp.MixProject do
                                                                                        
    use Mix.Project

    @version "0.2.0"

    @source_url "https://github.com/2p4b/wamp"

    def project do
        [
            app: :wamp,
            version: @version,
            elixir: "~> 1.18",
            start_permanent: false,
            deps: deps(),
            docs: docs(),
            name: "Wamp",
            package: package(),
            description: description(),
            source_url: @source_url 
        ]
    end

    # Run "mix help compile.app" to learn about applications.
    def application do
        [
          extra_applications: [:logger]
        ]
    end

    defp description() do
        "Wamp protocol lib"
    end

    defp package() do
        [
            # This option is only needed when you don't want to use the OTP application name
            name: "wamp",
            # These are the default files included in the package
            files: ~w(lib mix.exs README.md),
            maintainers: ["Che Mfoncho"],
            licenses: ["MIT"],
            links: %{"GitHub" => @source_url}
        ]
    end

    def docs() do
        [
            main: "readme",
            name: "Wamp",
            source_ref: "v#{@version}",
            canonical: "http://hexdocs.pm/wamp",
            source_url: @source_url,
            extras: ["README.md", "LICENSE"]
        ]
    end

    # Run "mix help deps" to learn about dependencies.
    defp deps do
        [
          # {:dep_from_hexpm, "~> 0.3.0"},
          # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
            {:jason, "~> 1.4"},
            {:msgpax, "~> 2.4"},
            {:phoenix_pubsub, "~> 2.0"},
            {:ex_doc, "~> 0.14", only: :dev, runtime: false}
        ]
    end
end
