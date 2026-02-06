defmodule Wamp do
    @moduledoc """
    A WAMP (Web Application Messaging Protocol) implementation for Elixir.

    WAMP is an open standard protocol that provides two messaging patterns
    over a single connection:

      * **Publish & Subscribe (PubSub)** - loosely coupled, many-to-many communication
      * **Remote Procedure Calls (RPC)** - routed, point-to-point communication

    ## Architecture

    The library is organized around the following core components:

      * `Wamp.Router` - Central message router that manages sessions and coordinates
        the broker and dealer
      * `Wamp.PubSub.Broker` - Handles publish/subscribe messaging
      * `Wamp.RPC.Dealer` - Handles remote procedure call routing
      * `Wamp.Client` - Client-side WAMP protocol implementation
      * `Wamp.Subscriber` - GenServer wrapper for event subscription handlers
      * `Wamp.Transport.Phoenix` - Phoenix WebSocket transport adapter

    ## OTP Application

    The `Wamp` module serves as the OTP application entry point. It starts a
    supervision tree under `Wamp.Supervisor` with a `:one_for_one` strategy.

    Routers and clients are started separately and should be added to your
    application's supervision tree.

    ## Quick Start

        # Define a router
        defmodule MyApp.Router do
          use Wamp.Router, otp_app: :my_app
        end

        # Define a client
        defmodule MyApp.Client do
          use Wamp.Client, otp_app: :my_app
        end

        # Start them in your supervision tree
        children = [
          {MyApp.Router, realm: "realm1"},
          {MyApp.Client, realm: "realm1", router: MyApp.Router}
        ]
    """

    use Application

    @doc false
    def start(_type, _args) do

        children = [
        ]

        Supervisor.start_link(children, strategy: :one_for_one, name: Wamp.Supervisor)
    end

    @doc """
    Returns `:world`. A simple test function.

    ## Examples

        iex> Wamp.hello()
        :world

    """
    def hello do
        :world
    end

end
