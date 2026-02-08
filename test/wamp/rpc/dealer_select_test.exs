defmodule Wamp.Test.MockRouter do
    @moduledoc false
    use GenServer

    def start_link do
        GenServer.start_link(__MODULE__, [])
    end

    @impl true
    def init(_), do: {:ok, %{messages: [], next_id: 1}}

    @impl true
    def handle_call({:nextid, _sid}, _from, state) do
        id = state.next_id
        {:reply, {:ok, id}, %{state | next_id: id + 1}}
    end

    @impl true
    def handle_call(:messages, _from, state) do
        {:reply, Enum.reverse(state.messages), state}
    end

    @impl true
    def handle_call(:clear, _from, state) do
        {:reply, :ok, %{state | messages: []}}
    end

    @impl true
    def handle_info({:push, sid, payload}, state) do
        {:noreply, %{state | messages: [{sid, payload} | state.messages]}}
    end

    @impl true
    def handle_info(_msg, state), do: {:noreply, state}
end

defmodule Wamp.Test.DisclosingDealer do
    @moduledoc false

    def register({_uri, _opts}, _session), do: {:ok, nil}

    def select({_uri, _call}, [proc | _], %{id: caller_id}) do
        {:ok, proc, %{callee: caller_id}}
    end

    def unregistered(_), do: nil
end

defmodule Wamp.RPC.DealerSelectTest do
    use ExUnit.Case
    use Wamp.Spec

    alias Wamp.Test.MockRouter

    defp register_procedure(dealer, router, uri, session) do
        send(dealer, {[@register, 1, %{}, uri], session})
        Process.sleep(150)

        messages = GenServer.call(router, :messages)
        Enum.find_value(messages, fn
            {_sid, [@registered, _req, regid]} -> regid
            _ -> nil
        end)
    end

    describe "call routing with default select (returns {:ok, proc})" do
        setup do
            {:ok, router} = MockRouter.start_link()
            args = [realm: "sel_default", router: router, dealer: Wamp.Example.Dealer]
            {:ok, dealer} = Wamp.RPC.Dealer.start_link(args)

            on_exit(fn ->
                if Process.alive?(dealer), do: GenServer.stop(dealer)
                if Process.alive?(router), do: GenServer.stop(router)
            end)

            %{dealer: dealer, router: router}
        end

        test "sends invocation to callee on successful call", ctx do
            callee = %{id: 10, pid: self(), auth: %{}}
            caller = %{id: 20, pid: self(), auth: %{}}

            regid = register_procedure(ctx.dealer, ctx.router, "com.test.add", callee)
            assert regid != nil

            GenServer.call(ctx.router, :clear)

            send(ctx.dealer, {[@call, 5, %{}, "com.test.add", [1, 2], %{}], caller})
            Process.sleep(100)

            messages = GenServer.call(ctx.router, :messages)
            inv = Enum.find(messages, fn {_sid, [type | _]} -> type == @invocation end)
            assert inv != nil

            {10, [@invocation, _reqid, ^regid, _details, [1, 2], %{}]} = inv
        end

        test "adds caller id to details when disclose_me is set", ctx do
            callee = %{id: 10, pid: self(), auth: %{}}
            caller = %{id: 20, pid: self(), auth: %{}}

            register_procedure(ctx.dealer, ctx.router, "com.test.disc", callee)
            GenServer.call(ctx.router, :clear)

            send(ctx.dealer, {[@call, 5, %{"disclose_me" => true}, "com.test.disc", [], %{}], caller})
            Process.sleep(100)

            messages = GenServer.call(ctx.router, :messages)
            {_, [@invocation, _, _, details, _, _]} =
                Enum.find(messages, fn {_sid, [type | _]} -> type == @invocation end)

            assert details[:caller] == 20
        end

        test "returns error for non-existent procedure", ctx do
            caller = %{id: 20, pid: self(), auth: %{}}

            send(ctx.dealer, {[@call, 5, %{}, "com.test.missing", [], %{}], caller})
            Process.sleep(50)

            messages = GenServer.call(ctx.router, :messages)
            err = Enum.find(messages, fn {_sid, [type | _]} -> type == @error end)
            assert err != nil

            {20, [@error, @call, 5, %{}, "wamp.error.procedure_not_found"]} = err
        end
    end

    describe "call routing with custom select (returns {:ok, proc, details})" do
        setup do
            {:ok, router} = MockRouter.start_link()
            args = [realm: "sel_custom", router: router, dealer: Wamp.Test.DisclosingDealer]
            {:ok, dealer} = Wamp.RPC.Dealer.start_link(args)

            on_exit(fn ->
                if Process.alive?(dealer), do: GenServer.stop(dealer)
                if Process.alive?(router), do: GenServer.stop(router)
            end)

            %{dealer: dealer, router: router}
        end

        test "passes custom details from select to invocation", ctx do
            callee = %{id: 10, pid: self(), auth: %{}}
            caller = %{id: 20, pid: self(), auth: %{}}

            register_procedure(ctx.dealer, ctx.router, "com.test.custom", callee)
            GenServer.call(ctx.router, :clear)

            send(ctx.dealer, {[@call, 5, %{}, "com.test.custom", [], %{}], caller})
            Process.sleep(100)

            messages = GenServer.call(ctx.router, :messages)
            {_, [@invocation, _, _, details, _, _]} =
                Enum.find(messages, fn {_sid, [type | _]} -> type == @invocation end)

            # Custom dealer returns %{callee: caller_id}
            assert details[:callee] == 20
        end

        test "merges disclose_me into custom details", ctx do
            callee = %{id: 10, pid: self(), auth: %{}}
            caller = %{id: 20, pid: self(), auth: %{}}

            register_procedure(ctx.dealer, ctx.router, "com.test.both", callee)
            GenServer.call(ctx.router, :clear)

            opts = %{"disclose_me" => true}
            send(ctx.dealer, {[@call, 5, opts, "com.test.both", [], %{}], caller})
            Process.sleep(100)

            messages = GenServer.call(ctx.router, :messages)
            {_, [@invocation, _, _, details, _, _]} =
                Enum.find(messages, fn {_sid, [type | _]} -> type == @invocation end)

            assert details[:callee] == 20
            assert details[:caller] == 20
        end
    end
end
