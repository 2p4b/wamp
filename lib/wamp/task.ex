defmodule Wamp.Task do

    @enforce_keys [:pid, :owner, :request]

    defstruct [ 
        :pid, 
        :owner, 
        :request,
        queue: [],
    ]

    use GenServer

    def name(request) do
        request
        |> Integer.to_string()
        |> String.to_atom()
    end

    def start_link(default) do
        request =  Keyword.get(default, :request)
        GenServer.start_link(__MODULE__, default, name: name(request) )
    end

    @impl true
    def init(opts) do
        {:ok, 
            %Wamp.Task{ 
                pid: self(),
                owner: Keyword.get(opts, :owner),
                request: Keyword.get(opts, :request)
            }
        }
    end

    @impl true
    def handle_info({:result, message}, state) do
        {:noreply, Map.update!(state, :queue, &(&1 ++ [{:result, message}]))}
    end

    @impl true
    def handle_info({:yield, message}, state) do
        {:noreply, Map.update!(state, :queue, &(&1 ++ [{:yield, message}]))}
    end

    @impl true
    def handle_info(unknown, state) do
        IO.inspect(unknown)
        {:noreply, state}
    end

    @impl true
    def handle_call({:state, key}, _, state) when is_atom(key) do
        {:reply, Map.get(state, key), state}
    end

    @impl true
    def handle_call(:state, _, state) do
        {:reply, state, state}
    end

    @impl true
    def handle_call(:shift, _, state) do
        [head | tail] = state.queue
        {:reply, head, Map.update!(state, :queue, fn _ -> tail end)}
    end

    @impl true
    def handle_call(:size, _, state) do
        {:reply, length(state.queue), state}
    end

    defp shutdown(%Wamp.Task{} = task) do
        if Process.alive?(task.pid) do
            Process.exit(task.pid, :done)
        end
    end

    defp ensure_alive(%Wamp.Task{pid: pid}) when is_pid(pid) do
        if not Process.alive?(pid) do
            # todo raise task dead expection
            false
        end
    end

    def start(request) do
        with {:ok, pid} <- __MODULE__.start_link([request: request, owner: self]) do
            GenServer.call(pid, :state)
        end
    end

    def yield(%Wamp.Task{pid: pid} = task) when is_pid(pid) do
        ensure_alive(task)
        size = GenServer.call(pid, :size)
        if size > 0 do
            case GenServer.call(pid, :shift) do
                {:yield, message} ->
                    message
                {:result, result} ->
                    shutdown(task)
                    result
            end
        else
            yield(task)
        end
    end

    def await(%Wamp.Task{pid: pid} = task) when is_pid(pid) do
        result = yield(task)
        if Process.alive?(pid) do
            await(task)
        else
            result
        end
    end

end
