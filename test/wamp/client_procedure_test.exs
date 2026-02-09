defmodule Wamp.Client.ProcedureTest do
    use ExUnit.Case, async: true

    alias Wamp.Client

    defmodule FakeHandler do
        def add(_args, _kwargs, _details), do: {:ok, 42}
        def multiply(_args, _kwargs, _details), do: {:ok, 100}
    end

    describe "procedure macro" do
        defmodule ClientWithDefaults do
            Module.register_attribute(__MODULE__, :procedures, accumulate: true)
            require Wamp.Client
            Client.procedure("com.test.add", FakeHandler, :add)

            def procedures, do: @procedures
        end

        defmodule ClientWithOpts do
            Module.register_attribute(__MODULE__, :procedures, accumulate: true)
            require Wamp.Client
            Client.procedure("com.test.add", FakeHandler, :add, %{"invoke" => "roundrobin"})

            def procedures, do: @procedures
        end

        test "stores 4-tuple with empty map when no opts given" do
            [{uri, module, fun, opts}] = ClientWithDefaults.procedures()

            assert uri == "com.test.add"
            assert module == FakeHandler
            assert fun == :add
            assert opts == %{}
        end

        test "stores 4-tuple with custom opts" do
            [{uri, module, fun, opts}] = ClientWithOpts.procedures()

            assert uri == "com.test.add"
            assert module == FakeHandler
            assert fun == :add
            assert opts == %{"invoke" => "roundrobin"}
        end
    end

    describe "__welcome__/3 procedure registration" do
        setup do
            # A minimal client state that __welcome__ expects
            router = spawn(fn -> flush_loop() end)

            state = %{
                id: nil,
                status: :connecting,
                details: nil,
                procedures: [],
                subscriptions: [],
                next_id: 1,
                router: router,
                pid: self()
            }

            on_exit(fn -> Process.exit(router, :kill) end)

            {:ok, state: state}
        end

        test "registers procedure with default empty opts", %{state: state} do
            procedures = [{"com.test.add", FakeHandler, :add, %{}}]
            channels = []

            result = Client.__welcome__({1, %{}}, {procedures, channels}, state)

            assert [proc] = result.procedures
            assert proc.uri == "com.test.add"
            assert proc.details == %{}
            assert proc.handler == {FakeHandler, :add}
            assert proc.status == :pending
        end

        test "registers procedure with custom opts", %{state: state} do
            opts = %{"invoke" => "roundrobin"}
            procedures = [{"com.test.add", FakeHandler, :add, opts}]
            channels = []

            result = Client.__welcome__({1, %{}}, {procedures, channels}, state)

            assert [proc] = result.procedures
            assert proc.uri == "com.test.add"
            assert proc.details == %{"invoke" => "roundrobin"}
            assert proc.handler == {FakeHandler, :add}
        end

        test "registers multiple procedures with different opts", %{state: state} do
            procedures = [
                {"com.test.add", FakeHandler, :add, %{}},
                {"com.test.multiply", FakeHandler, :multiply, %{"invoke" => "roundrobin"}}
            ]

            result = Client.__welcome__({1, %{}}, {procedures, []}, state)

            assert [proc1, proc2] = result.procedures
            assert proc1.uri == "com.test.add"
            assert proc1.details == %{}
            assert proc2.uri == "com.test.multiply"
            assert proc2.details == %{"invoke" => "roundrobin"}
        end

        test "sets session id and connected status", %{state: state} do
            result = Client.__welcome__({42, %{"roles" => %{}}}, {[], []}, state)

            assert result.id == 42
            assert result.status == :connected
            assert result.details == %{"roles" => %{}}
        end
    end

    # Simple process that receives and discards messages (acts as fake router)
    defp flush_loop do
        receive do
            _ -> flush_loop()
        end
    end
end
