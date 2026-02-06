defmodule Wamp.Example.Broker do
    @moduledoc """
    Example broker implementation that approves all subscriptions and publishes
    to all matching subscribers.

    This is the default broker used when no custom broker is specified in
    `use Wamp.Router`. Override this with your own module to add authorization,
    filtering, or custom logic.

    ## Implementing a Custom Broker

        defmodule MyApp.Broker do
          @behaviour Wamp.Broker

          def publish({topic, event}, publisher, subscribers) do
            # Filter or transform subscribers
            {:ok, subscribers}
          end

          def subscribe(topic, opts, session) do
            # Return {:ok, attributes} to approve or {:error, reason} to reject
            {:ok, []}
          end

          def unsubscribed(subscription) do
            # Cleanup after unsubscription
          end
        end
    """

    @behaviour Wamp.Broker

    @doc "Approves all publications and returns all subscribers."
    def publish({_topic, _event}, _publisher, subscribers) do
        {:ok, subscribers}
    end

    @doc "Approves all subscription requests."
    def subscribe(_topic, _opts, _session) do
        { :ok, []}
    end

    @doc "No-op cleanup after unsubscription."
    def unsubscribed(_subsciption) do
    end

end
