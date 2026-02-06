defmodule Wamp.Subscriber do
    @moduledoc """
    GenServer wrapper for handling WAMP event subscriptions.

    Use `use Wamp.Subscriber` in your module to define a subscriber that
    receives events from a WAMP topic. The subscriber is automatically started
    when a subscription is confirmed.

    ## Usage

        defmodule MyApp.ChatSubscriber do
          use Wamp.Subscriber

          def init(subscription) do
            # Optional initialization
            subscription
          end

          def handle_event({pubid, details, args, kwargs}, sub) do
            IO.inspect(args, label: "Received event")
            {:noreply, sub}
          end
        end

    ## Callbacks

    The following callbacks are overridable:

      * `init/1` - Initialize the subscriber with the subscription struct.
        Return the (possibly modified) subscription.
      * `handle_event/2` - Called when an event is received. Receives
        `{pubid, details, args, kwargs}` and the subscription state.
        Must return `{:noreply, sub}`.
      * `handle_info/2` - Handle arbitrary messages
      * `handle_call/3` - Handle synchronous calls
      * `handle_cast/2` - Handle asynchronous casts
      * `terminate/2` - Cleanup on termination
    """

    use GenServer

    defmodule Subscription do
        @moduledoc """
        Subscription state passed to subscriber callbacks.

        ## Fields

          * `:id` - the subscription ID
          * `:realm` - the WAMP realm name
        """
        @enforce_keys [:id, :realm]
        defstruct [:id, :realm]
    end

    defmacro __using__(_opts) do
        quote do

            def init(subscription) do
                subscription
            end

            def handle_event({_pubid, _details, _args, _kwargs}, sub) do
                {:noreply, sub}
            end

            def terminate(reason, state) do
            end

            defoverridable init: 1

            defoverridable terminate: 2

            defoverridable handle_event: 2

        end
    end

    @doc """
    Starts a subscriber process linked to the calling process.

    ## Options

      * `:id` - the subscription ID
      * `:realm` - the WAMP realm name
      * `:subscriber` - the subscriber callback module
    """
    def start_link(opts) do
        subscriber = Keyword.get(opts, :subscriber)
        GenServer.start_link(__MODULE__, opts, name: subscriber)
    end

    def init(opts) do
        opts = for {key, val} <- opts, into: %{}, do: {key, val}

        subscription = apply(opts.subscriber, :init, [
            %Wamp.Subscriber.Subscription{id: opts.id, realm: opts.realm}
        ])

        {:ok, Map.put(opts, :subscription, subscription)}
    end

    def handle_info({36, pubid, details, args, kwargs}, state) do
        %{subscription: sub, subscriber: subscriber} = state
        case apply(subscriber, :handle_event, [{pubid, details, args, kwargs}, sub]) do

            {:noreply, sub} ->
                {:noreply, Map.put(state, :subscription, sub)}

            {:noreply, sub, other} ->
                {:noreply, Map.put(state, :subscription, sub), other}

            reply -> reply
        end
    end

    def handle_info(msg, state) do
        %{subscription: sub, subscriber: subscriber} = state
        case apply(subscriber, :handle_info, [msg, sub]) do

            {:noreply, sub} ->
                {:noreply, Map.put(state, :subscription, sub)}

            {:noreply, sub, other} ->
                {:noreply, Map.put(state, :subscription, sub), other}

            reply -> reply
        end
    end

    def handle_call(msg, from, state) do
        %{subscription: sub, subscriber: subscriber} = state
        case apply(subscriber, :handle_call, [msg, from, sub]) do

            {:reply, reply, sub} ->
                {:reply, reply, Map.put(state, :subscription, sub)}

            {:reply, reply, sub, other} ->
                {:reply, reply, Map.put(state, :subscription, sub), other}

            {:noreply, sub} ->
                {:noreply, Map.put(state, :subscription, sub)}

            {:noreply, sub, other} ->
                {:noreply, Map.put(state, :subscription, sub), other}

            reply -> reply
        end
    end

    def handle_cast(msg, state) do
        %{subscription: sub, subscriber: subscriber} = state
        case apply(subscriber, :handle_cast, [msg, sub]) do

            {:noreply, sub} ->
                {:noreply, Map.put(state, :subscription, sub)}

            {:noreply, sub, other} ->
                {:noreply, Map.put(state, :subscription, sub), other}

            reply -> reply
        end
    end

    def terminate(reason, state) do
        apply(state.subscriber, :terminate, [reason, state.subscription])
    end

end
