defmodule Wamp.Example.Broker do

    @behaviour Wamp.Broker

    def publish({_topic, _event}, _publisher, subscribers) do
        {:ok, subscribers}
    end

    def subscribe(_topic, _opts, session) do
        { :ok, []}
    end

    def unsubscribed(_subsciption) do
    end

end
