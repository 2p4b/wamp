defmodule Wamp.SubscriberTest do
    use ExUnit.Case

    defmodule TestSubscriber do
        use Wamp.Subscriber

        def init(subscription) do
            send(subscription.realm |> String.to_atom(), {:init_called, subscription})
            subscription
        end

        def handle_event({pubid, details, args, kwargs}, sub) do
            send(sub.realm |> String.to_atom(), {:event, pubid, details, args, kwargs})
            {:noreply, sub}
        end
    end

    describe "subscriber lifecycle" do
        test "starts and calls init callback" do
            Process.register(self(), :test_realm_init)

            {:ok, pid} = Wamp.Subscriber.start_link(
                id: 1,
                realm: "test_realm_init",
                subscriber: TestSubscriber
            )

            assert Process.alive?(pid)

            assert_receive {:init_called, %Wamp.Subscriber.Subscription{id: 1, realm: "test_realm_init"}}

            GenServer.stop(pid)
        end

        test "handles events via callback" do
            Process.register(self(), :test_realm_event)

            {:ok, pid} = Wamp.Subscriber.start_link(
                id: 2,
                realm: "test_realm_event",
                subscriber: TestSubscriber
            )

            # Send an event message (message type 36 = @event)
            send(pid, {36, 100, %{}, ["hello"], %{"key" => "value"}})

            assert_receive {:event, 100, %{}, ["hello"], %{"key" => "value"}}

            GenServer.stop(pid)
        end
    end
end
