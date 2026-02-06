defmodule Wamp.Example.Dealer do

    @behaviour Wamp.Dealer

    def register({_topic, _opts}, _session) do
        {:ok, nil}
    end

    def procedure({_topic, _call}, _caller, [proc | _]) do
        { :ok, proc}
    end

    def unregistered(_) do
    end

end
