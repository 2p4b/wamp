defmodule Wamp.Transport.Phoenix do

    use Wamp.Spec


    defmacro __using__(opts) do

        router = Keyword.get(opts, :router)

        quote do

            @router unquote(router)

            @behaviour Phoenix.Socket.Transport

            def child_spec(opts) do
                Wamp.Transport.Phoenix.__child_spec__(opts)
            end

            def connect(connection) do 
                Wamp.Transport.Phoenix.__connect__(__MODULE__, connection)
            end

            def init(state) do 
                Wamp.Transport.Phoenix.__init__(state)
            end

            def handle_in(_, %{goodbye: %{}} = state) do
                {:ok, state}
            end

            def handle_in({data, [opcode: _opcode]}, state) do
                Wamp.Transport.Phoenix.__handle_in__(@router, data, state)
            end

            def handle_info(payload, state) when is_list(payload) do
                Wamp.Transport.Phoenix.__push_message__(payload, state)
            end

            def handle_info({:shutdown, reason}, state) do
                {:stop, reason, state}
            end

            def terminate(_reason, _state) do
                :ok
            end

        end

    end

    def __child_spec__(_opts) do
        # We won't spawn any process, so let's return a dummy task
        %{id: Task, start: {Task, :start_link, [fn -> :ok end]}, restart: :transient}
    end

    def __connect__(transport, map) do
        # Callback to retrieve relevant data from the connection.
        # The map contains options, params, transport and endpoint keys.
        subprotocol = 
            Keyword.get(map.options, :subprotocols, ["wamp.2.json"])
            |> Enum.find( fn 
                "wamp.2."<> opcode -> 
                    opcode === "json" or opcode === "msgpack"
                _ -> false
            end)

        protocol = 
            if is_nil(subprotocol) do
                :json
            else
                "wamp.2."<> code = subprotocol
                String.to_atom(code)
            end

        socket = %{
            info: map.connect_info,
            params: map.params,
            protocol: protocol,
            transport: map.transport,
        }

        with {:ok, conn} <- transport.connection(socket) do
            {:ok, %{ socket: socket, conn: conn }}
        else
            error -> error
        end
    end

    def __init__(state) do
        # Now we are effectively inside the process that maintains the socket.
        {:ok, state}
    end

    defp decode({:text, payload}) do
        payload
        |> Jason.decode()
    end

    defp decode({:json, payload}) do
        payload
        |> Jason.decode()
    end

    defp decode({:msgpack, payload}) do
        payload
        |> MessagePack.unpack()
    end

    defp encode({:text, payload}) do
        payload
        |> Jason.encode()
    end

    defp encode({:json, payload}) do
        payload
        |> Jason.encode()
    end

    defp encode({:msgpack, payload}) do
        payload
        |> MessagePack.pack()
    end

    def __handle_in__(router, data, state) do

        with {:ok, message} <- decode({state.socket.protocol, data}) do

            message =
                case message do
                    [@hello, realm, details] ->
                        [@hello, realm, details, state.conn]

                    _ ->
                        message
                end

            router.send(message)

            {:ok, check_for_termination(message, state)}

        else
            _ -> 
                {:ok, state}
        end

    end


    def __push_message__(message, state) when is_list(message) do

        {:ok, data } = encode({state.socket.protocol, message})

        opcode = 
            if state.socket.protocol === :msgpack do
                :binary
            else
                :text
            end

        {:reply, :ok, {opcode, data}, check_for_termination(message, state)}
    end

    defp shutdown(reason) do
        send(self(), {:shutdown, reason})
    end

    defp check_for_termination([@abort, details, reason], state) do
        abort = %{details: details, reason: reason}
        shutdown(abort)
        Map.put(state, :abort, abort)
    end

    defp check_for_termination([@goodbye, _, "wamp.close.goodbye_and_out"], state) do
        shutdown(Map.get(state, :goodbye))
        state
    end

    defp check_for_termination([@goodbye, details, reason], state) do
        goodbye = %{details: details, reason: reason}
        Map.put(state, :goodbye, goodbye)
    end

    defp check_for_termination(_, state) do
        state
    end
end
