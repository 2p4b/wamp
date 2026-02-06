defmodule Wamp.Spec.Broker do
    @moduledoc """
    Behaviour for custom WAMP broker implementations.

    A broker controls how publish/subscribe operations are handled. Implement
    this behaviour to add custom authorization, filtering, or side effects
    to pub/sub operations.

    See `Wamp.Example.Broker` for a reference implementation.

    ## Callbacks

      * `capabilities/2` - Return a map of broker capabilities for a session
      * `publish/2` - Called when a client publishes an event to a topic
      * `subscribe/2` - Called when a client subscribes to a topic
      * `unsubscribe/1` - Called when a subscription is removed
    """

    @callback capabilities(Integer.t, Map.t) :: Map.t

    @callback publish(String.t, Map.t) :: {:ok, Integer.t} | :error

    @callback subscribe(String.t, Function.t) :: {:ok, Integer.t} | :error

    @callback unsubscribe(Integer.t) :: :ok | :error

end
