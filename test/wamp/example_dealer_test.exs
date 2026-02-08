defmodule Wamp.Example.DealerTest do
    use ExUnit.Case, async: true

    alias Wamp.RPC.Procedure

    describe "select/3" do
        test "returns first procedure from a multi-element list" do
            proc1 = %Procedure{id: 1, sid: 10, uri: "com.test.add", status: :registered}
            proc2 = %Procedure{id: 2, sid: 20, uri: "com.test.add", status: :registered}
            caller = %{id: 100, pid: self()}

            assert {:ok, ^proc1} =
                Wamp.Example.Dealer.select({"com.test.add", %{}}, [proc1, proc2], caller)
        end

        test "returns single procedure from singleton list" do
            proc = %Procedure{id: 1, sid: 10, uri: "com.test.add", status: :registered}
            caller = %{id: 100}

            assert {:ok, ^proc} =
                Wamp.Example.Dealer.select({"com.test.add", %{}}, [proc], caller)
        end

        test "returns {:ok, proc, details} for wamp-prefixed singleton" do
            proc = %Procedure{id: 1, sid: 10, uri: "wamp.session.list", status: :registered}
            caller = %{id: 42}

            assert {:ok, ^proc, %{callee: 42}} =
                Wamp.Example.Dealer.select({"wamp.session.list", %{}}, [proc], caller)
        end

        test "falls back to generic clause for multi-element wamp list" do
            proc1 = %Procedure{id: 1, sid: 10, uri: "wamp.session.list", status: :registered}
            proc2 = %Procedure{id: 2, sid: 20, uri: "wamp.session.list", status: :registered}
            caller = %{id: 42}

            # Multi-element list doesn't match the singleton wamp clause
            assert {:ok, ^proc1} =
                Wamp.Example.Dealer.select({"wamp.session.list", %{}}, [proc1, proc2], caller)
        end

        test "falls back to generic clause for non-wamp singleton" do
            proc = %Procedure{id: 1, sid: 10, uri: "com.test.add", status: :registered}
            caller = %{id: 42}

            assert {:ok, ^proc} =
                Wamp.Example.Dealer.select({"com.test.add", %{}}, [proc], caller)
        end
    end

    describe "register/2" do
        test "approves all registrations with nil attributes" do
            session = %{id: 1, pid: self()}
            assert {:ok, nil} = Wamp.Example.Dealer.register({"com.test.add", %{}}, session)
        end
    end
end
