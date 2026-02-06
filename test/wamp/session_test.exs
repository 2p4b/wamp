defmodule Wamp.SessionTest do
    use ExUnit.Case, async: true

    describe "struct creation" do
        test "creates session with required fields" do
            session = %Wamp.Session{id: 1, pid: self()}
            assert session.id == 1
            assert session.pid == self()
            assert session.details == %{}
            assert session.request_count == 0
        end

        test "creates session with all fields" do
            session = %Wamp.Session{
                id: 42,
                pid: self(),
                details: %{"transport" => "websocket"},
                request_count: 5
            }
            assert session.id == 42
            assert session.details == %{"transport" => "websocket"}
            assert session.request_count == 5
        end

        test "enforces :id key" do
            assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
                struct!(Wamp.Session, pid: self())
            end
        end

        test "enforces :pid key" do
            assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
                struct!(Wamp.Session, id: 1)
            end
        end
    end
end
