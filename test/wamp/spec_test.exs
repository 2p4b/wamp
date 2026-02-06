defmodule Wamp.SpecTest do
    use ExUnit.Case, async: true

    defmodule TestSpec do
        use Wamp.Spec

        def get_hello, do: @hello
        def get_welcome, do: @welcome
        def get_abort, do: @abort
        def get_challenge, do: @challenge
        def get_authenticate, do: @authenticate
        def get_goodbye, do: @goodbye
        def get_error, do: @error
        def get_publish, do: @publish
        def get_published, do: @published
        def get_subscribe, do: @subscribe
        def get_subscribed, do: @subscribed
        def get_unsubscribe, do: @unsubscribe
        def get_unsubscribed, do: @unsubscribed
        def get_event, do: @event
        def get_call, do: @call
        def get_cancel, do: @cancel
        def get_result, do: @result
        def get_register, do: @register
        def get_registered, do: @registered
        def get_unregister, do: @unregister
        def get_unregistered, do: @unregistered
        def get_invocation, do: @invocation
        def get_interrupt, do: @interrupt
        def get_yield, do: @yield
        def get_max_id, do: @max_id
    end

    describe "session lifecycle constants" do
        test "hello is 1" do
            assert TestSpec.get_hello() == 1
        end

        test "welcome is 2" do
            assert TestSpec.get_welcome() == 2
        end

        test "abort is 3" do
            assert TestSpec.get_abort() == 3
        end

        test "challenge is 4" do
            assert TestSpec.get_challenge() == 4
        end

        test "authenticate is 5" do
            assert TestSpec.get_authenticate() == 5
        end

        test "goodbye is 6" do
            assert TestSpec.get_goodbye() == 6
        end

        test "error is 8" do
            assert TestSpec.get_error() == 8
        end
    end

    describe "pubsub constants" do
        test "publish is 16" do
            assert TestSpec.get_publish() == 16
        end

        test "published is 17" do
            assert TestSpec.get_published() == 17
        end

        test "subscribe is 32" do
            assert TestSpec.get_subscribe() == 32
        end

        test "subscribed is 33" do
            assert TestSpec.get_subscribed() == 33
        end

        test "unsubscribe is 34" do
            assert TestSpec.get_unsubscribe() == 34
        end

        test "unsubscribed is 35" do
            assert TestSpec.get_unsubscribed() == 35
        end

        test "event is 36" do
            assert TestSpec.get_event() == 36
        end
    end

    describe "rpc constants" do
        test "call is 48" do
            assert TestSpec.get_call() == 48
        end

        test "cancel is 49" do
            assert TestSpec.get_cancel() == 49
        end

        test "result is 50" do
            assert TestSpec.get_result() == 50
        end

        test "register is 64" do
            assert TestSpec.get_register() == 64
        end

        test "registered is 65" do
            assert TestSpec.get_registered() == 65
        end

        test "unregister is 66" do
            assert TestSpec.get_unregister() == 66
        end

        test "unregistered is 67" do
            assert TestSpec.get_unregistered() == 67
        end

        test "invocation is 68" do
            assert TestSpec.get_invocation() == 68
        end

        test "interrupt is 69" do
            assert TestSpec.get_interrupt() == 69
        end

        test "yield is 70" do
            assert TestSpec.get_yield() == 70
        end
    end

    describe "max_id" do
        test "max_id is 2^53" do
            assert TestSpec.get_max_id() == 9_007_199_254_740_992
        end
    end
end
