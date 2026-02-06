defmodule Wamp.Task do
    @moduledoc """
    GenServer for managing request-specific message queuing and result handling.

    A task process is created per request and queues incoming result and yield
    messages. It provides blocking `yield/1` and `await/1` functions to
    consume results.

    ## Fields

      * `:pid` - (required) the task process PID
      * `:owner` - (required) the owning process PID
      * `:request` - (required) the request ID this task handles
      * `:queue` - message queue of `{:result, msg}` and `{:yield, msg}` tuples
    """

    @enforce_keys [:pid, :owner, :request]

    defstruct [
        :pid,
        :owner,
        :request,
        queue: [],
    ]

    use GenServer

    @doc """
    Returns the registered process name for the given request ID.
    """
    def name(request) do
        request
        |> Integer.to_string()
        |> String.to_atom()
    end

    @doc """
    Starts a task process linked to the calling process.

    ## Options

      * `:request` - (required) the request ID
      * `:owner` - (required) the owning process PID
    """
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

    @doc """
    Creates a new task process for the given request and returns its state.
    """
    def start(request) do
        with {:ok, pid} <- __MODULE__.start_link([request: request, owner: self()]) do
            GenServer.call(pid, :state)
        end
    end

    @doc """
    Blocks until the next message is available in the queue and returns it.

    If the message is a `:result`, the task process is shut down.
    If the message is a `:yield`, it is returned and the task continues.
    """
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

    @doc """
    Blocks until the task process is complete, returning the final result.

    Repeatedly calls `yield/1` until the task process is no longer alive.
    """
    def await(%Wamp.Task{pid: pid} = task) when is_pid(pid) do
        result = yield(task)
        if Process.alive?(pid) do
            await(task)
        else
            result
        end
    end

end
