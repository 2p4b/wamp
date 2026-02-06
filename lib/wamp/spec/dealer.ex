defmodule Wamp.Spec.Dealer do
    @moduledoc """
    Behaviour for custom WAMP dealer implementations.

    A dealer controls how remote procedure calls are routed. Implement this
    behaviour to add custom authorization, procedure selection, or side effects
    to RPC operations.

    See `Wamp.Example.Dealer` for a reference implementation.

    ## Callbacks

      * `capabilities/2` - Return a map of dealer capabilities for a session
      * `yield/2` - Called when an invocation yields a result
      * `cancel/2` - Called when a call is cancelled
      * `invoke/2` - Called to invoke a registered procedure
    """

    @callback capabilities(Integer.t, Map.t) :: Map.t

    @callback yield(Integer.t, Map.t) :: :ok | :error

    @callback cancel(Integer.t, String.t) :: :ok | :error

    @callback invoke(String.t, List.t) :: {:ok, Integer.t} | :error

end
