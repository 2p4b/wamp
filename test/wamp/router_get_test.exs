defmodule Wamp.Test.GetRouter do
    use Wamp.Router,
        dealer: Wamp.Example.Dealer,
        broker: Wamp.Example.Broker
end

defmodule Wamp.Router.GetTest do
    use ExUnit.Case

    @realm "test_get_realm"

    setup do
        {:ok, pid} = Wamp.Test.GetRouter.start_link(realm: @realm)

        on_exit(fn ->
            if Process.alive?(pid), do: GenServer.stop(pid)
        end)

        %{router: pid}
    end

    describe "path-based get with list" do
        test "resolves top-level atom key", %{router: router} do
            assert GenServer.call(router, {:get, [:realm]}) == @realm
        end

        test "returns nil for missing key", %{router: router} do
            assert GenServer.call(router, {:get, [:nonexistent]}) == nil
        end

        test "returns sessions list", %{router: router} do
            assert GenServer.call(router, {:get, [:sessions]}) == []
        end

        test "finds session by id after connection", %{router: router} do
            # Create a session via HELLO (msg type 1), anonymous auth auto-welcomes
            send(router, {[1, @realm, %{}, :elixir], self()})
            assert_receive [2, sid, _details], 1000

            session = GenServer.call(router, {:get, [:sessions, sid]})
            assert session.id == sid
            assert session.pid == self()
            assert session.auth != nil
        end

        test "returns nil for non-existent session id", %{router: router} do
            assert GenServer.call(router, {:get, [:sessions, 999]}) == nil
        end

        test "resolves broker and dealer pids", %{router: router} do
            assert is_pid(GenServer.call(router, {:get, [:broker]}))
            assert is_pid(GenServer.call(router, {:get, [:dealer]}))
        end
    end

    describe "session/2" do
        test "finds session by id", %{router: router} do
            send(router, {[1, @realm, %{}, :elixir], self()})
            assert_receive [2, sid, _details], 1000

            session = GenServer.call(router, {:get, [:sessions, sid]})
            assert session.id == sid
        end
    end

    describe "atom-based get" do
        test "returns atom key value", %{router: router} do
            assert GenServer.call(router, {:get, :realm}) == @realm
        end

        test "returns nil for unknown atom key", %{router: router} do
            assert GenServer.call(router, {:get, :nonexistent}) == nil
        end
    end

end
