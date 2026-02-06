defmodule Wamp.Example.Subscriber do
    @moduledoc """
    Example event subscriber that receives events without performing any action.

    Demonstrates the minimal `Wamp.Subscriber` implementation.
    Override `handle_event/2` to process incoming events.
    """

    use Wamp.Subscriber

    @doc false
    def handle_event({_pubid, _details, _args, _kwargs}, sub) do
        {:noreply, sub}
    end

end
