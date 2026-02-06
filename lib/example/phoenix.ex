defmodule Wamp.Example.Phoenix do
    @moduledoc """
    Example Phoenix WebSocket transport for WAMP.

    Demonstrates the minimal `Wamp.Transport.Phoenix` implementation.
    The `connection/1` callback receives the socket and can be used
    for connection-level authorization.
    """

    use Wamp.Transport.Phoenix,
        router: Wamp.Example.Router

    @doc "Accepts all connections without modification."
    def connection(socket) do
        {:ok, socket}
    end

end
