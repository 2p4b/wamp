defmodule Wamp.Client do
    @moduledoc """
    WAMP client implementation supporting all four WAMP roles: caller, callee,
    publisher, and subscriber.

    A client connects to a router, joins a realm, and can then perform pub/sub
    and RPC operations.

    ## Usage

    Define a client module:

        defmodule MyApp.Client do
          use Wamp.Client, otp_app: :my_app

          # Auto-register procedures on connect
          procedure "math.add", MyApp.Math, :add
          procedure "math.multiply", MyApp.Math, :multiply

          # Auto-subscribe to topics on connect
          channel "events.user", MyApp.UserSubscriber
        end

    ## Configuration

        config :my_app, MyApp.Client,
          realm: "realm1",
          router: MyApp.Router

    ## Macros

      * `procedure(uri, module, function)` - Register a procedure handler that is
        automatically registered when the client connects
      * `channel(uri, subscriber_module)` - Subscribe to a topic that is
        automatically subscribed when the client connects

    ## Public Functions (injected via `use`)

    ### Connection

      * `start_link/1` - Start and connect the client
      * `state/1` - Get client state or a specific section
      * `goodbye/1` - Gracefully disconnect from the router

    ### Remote Procedure Calls

      * `call/2` - Call a procedure with positional args
      * `call/2` - Call a procedure with keyword args (map)
      * `call/3` - Call a procedure with both args and kwargs
      * `register/3` - Register a procedure handler
      * `unregister/1` - Unregister a procedure
      * `registered/1` - Check if a procedure is registered
      * `yield/1` - Get the result of a call
      * `yielded/1` - Check if a call result is ready
      * `await/1` - Block until a call result is available

    ### Publish & Subscribe

      * `subscribe/2` - Subscribe to a topic
      * `unsubscribe/1` - Unsubscribe from a topic
      * `subscribed/1` - Check if subscribed to a topic
      * `subscriptions/0` - List all subscriptions
      * `publish/2` - Publish an event (fire-and-forget)
      * `publish/3` - Publish with kwargs
      * `publish/4` - Publish with kwargs and options
      * `ack_publish/2` - Publish and wait for acknowledgment

    ## Procedure Handlers

    Procedure handlers are `{module, function}` tuples. The function receives
    `(args, kwargs, details)` and should return the result value. Raise
    `Wamp.Client.InvocationError` to return a WAMP error:

        def add(args, _kwargs, _details) do
          Enum.sum(args)
        end

        def divide([a, b], _kwargs, _details) do
          if b == 0 do
            raise Wamp.Client.InvocationError,
              uri: "com.error.division_by_zero",
              args: ["Cannot divide by zero"]
          end
          a / b
        end
    """

    use Wamp.Spec

    defmodule InvocationError do
        @moduledoc """
        Exception raised within procedure handlers to return a WAMP error
        to the caller.

        ## Fields

          * `:uri` - error URI (default: `"wamp.invocation.error"`)
          * `:args` - positional error arguments (default: `[]`)
          * `:kwargs` - keyword error arguments (default: `%{}`)

        ## Usage

            raise Wamp.Client.InvocationError,
              uri: "com.error.not_found",
              args: ["Resource not found"],
              kwargs: %{"id" => 42}
        """

        defexception [
            uri: "wamp.invocation.error",
            args: [],
            kwargs: %{}
        ]

        @impl true
        def message(exception) do
            exception.uri
        end

    end

    defmacro __using__(opts) do

        otp_app = Keyword.get(opts, :otp_app)

        conn = Keyword.get(opts, :connection, __MODULE__)

        quote do

            import Wamp.Client

            use Wamp.Spec

            use GenServer

            @before_compile Wamp.Client

            @conn unquote(conn)

            @otp_app unquote(otp_app)

            Module.register_attribute(__MODULE__, :channels, accumulate: true)

            Module.register_attribute(__MODULE__, :procedures, accumulate: true)

            if is_nil(@otp_app) do
                defp get_env() do
                    []
                end
            else
                defp get_env() do
                    case Application.get_env(@otp_app, __MODULE__) do
                        nil -> []
                        env -> env
                    end
                end
            end

            def start_link(opts) when is_list(opts) or is_nil(opts) do

                config = Application.get_env(@otp_app, __MODULE__, [])

                config =
                    if is_nil(opts) do
                        get_env()
                    else
                        opts ++ get_env()
                    end

                if not Keyword.has_key?(config, :realm) do
                    raise "Client config must have realm"
                end

                if not Keyword.has_key?(config, :router) do
                    raise "Client config must have router"
                end

                GenServer.start_link(__MODULE__, config, name: __MODULE__)
            end

            @impl true
            def init(args) do

                pid = self()

                state = %{ 
                    id: nil,
                    pid: pid,
                    realm: Keyword.get(args, :realm),
                    status: :disconnected,
                    router: Keyword.get(args, :router),
                    next_id: 1,
                    details: %{},
                    calls: [],
                    events: [],
                    results: [],
                    procedures: [],
                    invocations: [],
                    subscriptions: [],
                    roles: roles()
                }
                
                from = {pid, nil}

                {_, _, state} = handle_call(:connect, from, state)

                {:ok, state}
            end

            defp roles do
                %{
                    "caller" => %{
                        "features" => caller_features()
                    },

                    "callee" => %{
                        "features" => callee_features()
                    },

                    "publisher" => %{
                        "features" => publisher_features()
                    },

                    "subscriber" => %{
                        "features" => subscriber_features()
                    }
                }
            end

            defp caller_features do
                %{
                    "call_canceling" => true,
                    "caller_identification" => true,
                    "progressive_call_results" => false
                }
            end

            defp callee_features do
                %{
                    "shared_registration" => true,
                    "caller_identification" => true,
                    "registration_revocation" => true,
                    "progressive_call_results" => true,
                    "pattern_based_registration" => false,
                }
            end

            defp publisher_features do
                %{
                    "publisher_exclusion" => true,
                    "publisher_identification" => true,
                    "subscriber_blackwhite_listing" => true,
                }
            end

            defp subscriber_features do
                %{
                    "subscription_revocation" => true,
                    "publisher_identification" => true,
                    "pattern_based_subscription" => true,
                }
            end

            def handle_event(sub, details, args, kwargs) do
                send(sub.pid, {@event, details, args, kwargs})
            end

            @impl true
            def handle_call({:state, section}, _from, state) 
            when is_atom(section) or is_nil(section) do
                if is_nil(section) do
                    {:reply, state, state}
                else
                    {:reply, Map.get(state, section), state}
                end
            end

            @impl true
            def handle_call(:connect, _from, state) do
                {reply, state} = 
                    apply(Wamp.Client, :__handle_connect__, [state, @conn])
                {:reply, reply, state}
            end

            @impl true
            def handle_call(:subscriptions, _from, state) do
                {:reply, Map.get(state, :subscriptions), state}
            end

            @impl true
            def handle_call(:status, _from, state) do
                {:reply, Map.get(state, :status), state}
            end

            @impl true
            def handle_call(:id, _from, state) do
                {:reply, Map.get(state, :id), state}
            end

            @impl true
            def handle_call(:procedures, _from, state) do
                {:reply, Map.get(state, :procedures), state}
            end

            @impl true
            def handle_call({:result, request}, _from, state) do
                {result, state} = 
                    apply(Wamp.Client, :__handle_yield_result__, [request, state])

                {:reply, result, state}
            end

            @impl true
            def handle_call({:call_status, request}, _from, state) do
                {yielded, state} = 
                    apply(Wamp.Client, :__handle_call_status__, [request, state])

                {:reply, yielded, state}
            end

            @impl true
            def handle_call({:registered, uri}, _from, state) do
                {subscribed, state} = 
                    apply(Wamp.Client, :__handle_registered__, [uri, state])

                {:reply, subscribed, state}
            end

            @impl true
            def handle_call({:event_status, reqid}, _from, state) do
                {status, state} = 
                    apply(Wamp.Client, :__handle_event_status__, [reqid, state])

                {:reply, status, state}
            end

            @impl true
            def handle_call({:publication, reqid}, _from, state) do
                {publication, state} = 
                    apply(Wamp.Client, :__handle_yield_publication__, [reqid, state])

                {:reply, publication, state}
            end

            @impl true
            def handle_call({:subscribed, uri}, _from, state) do
                {subscribed, state} = 
                    apply(Wamp.Client, :__handle_subscribed__, [uri, state])

                {:reply, subscribed, state}
            end

            @impl true
            def handle_call({@goodbye, reason}, _from, state) when is_binary(reason) do
                {reply, state} = 
                    apply(Wamp.Client, :__handle_goodbye__, [reason, state])
                {:reply, reply, state}

            end

            @impl true
            def handle_call({@call, opts, uri, args, kwargs}, _from , state) do
                {reply, state} = 
                    apply(Wamp.Client, :__handle_call__, [{uri, opts, args, kwargs}, state])
                {:reply, reply, state}
            end

            @impl true
            def handle_call({@publish, opts, topic, args, kwargs}, _from, state) do

                {reply, state} = 
                    apply(Wamp.Client, :__handle_publish__, [{topic, opts, args, kwargs}, state])
                {:reply, reply, state}
            end

            @impl true
            def handle_call({@unregister, uri}, _from, state) do
                {reply, state} = 
                    apply(Wamp.Client, :__handle_unregister__, [uri, state])
                {:reply, reply, state}
            end

            @impl true
            def handle_call({@subscribe, opts, topic, subscriber}, _from , state) do

                {reply, state} = 
                    apply(Wamp.Client, :__handle_subscribe__, [{topic, opts, subscriber}, state])

                {:reply, reply, state}
            end

            @impl true
            def handle_call({@unsubscribe, topic}, _from , state) do
                {reply, state} = 
                    apply(Wamp.Client, :__handle_unsubscribe__, [topic, state])

                {:reply, reply, state}
            end

            def handle_call({@register, opts, uri, handler}, _from, state) do
                {reply, state} = 
                    apply(Wamp.Client, :__handle_register__, [{uri, opts, handler}, state])
                {:reply, reply, state}
            end

            @impl true
            def handle_call({@yield, res}, {pid, _ref}, state) do
                {reply, state} = 
                    apply(Wamp.Client, :__handle_yield__, [{res, pid}, state])

                {:reply, reply, state}
            end

            @impl true
            def handle_info([@welcome, id, details], state) do
                channels = __channels__()
                procedures = __procedures__()
                args = [{id, details}, {procedures, channels}, state]
                {:noreply, apply(Wamp.Client, :__welcome__, args)}
            end

            @impl true
            def handle_info([@challenge, _method, _details], state) do
                {reason, state} =
                    apply(Wamp.Client, :__challenge__, [state])
                {:stop, reason, state}
            end

            @impl true
            def handle_info([@abort, details, uri], state) do
                {:stop, uri, state}
            end

            @impl true
            def handle_info([@goodbye, details, uri], state) do
                {reason, state} =
                    apply(Wamp.Client, :__goodbye__, [state])
                {:stop, reason, state}
            end

            @impl true
            def handle_info([@published, request, pubid], state) do
                state =
                    apply(Wamp.Client, :__published__, [{request, pubid}, state])

                {:noreply, state}
            end

            @impl true
            def handle_info([@subscribed, request, subid], state) do
                state =
                    apply(Wamp.Client, :__subscribed__, [{request, subid}, state])

                {:noreply, state}
            end

            @impl true
            def handle_info([@unsubscribed, 0, %{"subscription" => subid, "reason" => reason}], state) do

                state =
                    apply(Wamp.Client, :__unsubscribed__, [{subid, reason}, state])

                {:noreply, state}
            end

            @impl true
            def handle_info([@unsubscribed, request], state) do
                state =
                    apply(Wamp.Client, :__unsubscribed__, [request, state])

                {:noreply, state}

            end

            @impl true
            def handle_info([@registered, request, regid], state) do

                state =
                    apply(Wamp.Client, :__registered__, [{request, regid}, state])

                {:noreply, state}
            end

            @impl true
            def handle_info([@unregistered, request], state) do

                state =
                    apply(Wamp.Client, :__unregistered__, [request, state])

                {:noreply, state}

            end

            @impl true
            def handle_info([@unregistered, 0, %{"registration" => regid, "reason" => reason}], state) do

                state =
                    apply(Wamp.Client, :__unregistered__, [{regid, reason}, state])

                {:noreply, state}
            end


            @impl true
            def handle_info([@event, subid, pubid, details], state) do
                handle_info([@event, subid, pubid, details, [], %{}], state)
            end

            @impl true
            def handle_info([@event, subid, pubid, details, args], state) do
                handle_info([@event, subid, pubid, details, args, %{}], state)
            end

            @impl true
            def handle_info([@event, subid, pubid, details, args, kwargs], state) do

                state =
                    apply(Wamp.Client, :__event__, [{subid, pubid, details, args, kwargs}, state])
                {:noreply, state}
            end


            @impl true
            def handle_info([@invocation, req, id, details, args, kwargs], state) do
                state =
                    apply(Wamp.Client, :__invocation__, [__MODULE__, {req, id, details, args, kwargs}, state])
                {:noreply, state}
            end

            @impl true
            def handle_info([@interrupt, req, details], state) do
                state =
                    apply(Wamp.Client, :__interrupt__, [{req, details}, state])
                {:noreply, state}
            end

            @impl true
            def handle_info([@result, request, details], state) do
                handle_info([@result, request, details, [], %{}], state)
            end

            @impl true
            def handle_info([@result, request, details, args], state) do
                handle_info([@result, request, details, args, %{}], state)
            end

            @impl true
            def handle_info([@result, request, details, args, kwargs], state) do
                state =
                    apply(Wamp.Client, :__result__, [{request, details, args, kwargs}, state])
                {:noreply, state}
            end

            @impl true
            def handle_info([@error, @register, request, details, uri], state) do
                state =
                    apply(Wamp.Client, :__register_error__, [{request, details, uri}, state])
                {:noreply, state}
            end

            @impl true
            def handle_info([@error, @subscribe, request, details, uri], state) do

                state =
                    apply(Wamp.Client, :__subscribe_error__, [{request, details, uri}, state])
                {:noreply, state}
            end

            @impl true
            def handle_info([@error, @publish, request, details, uri], state) do

                state =
                    apply(Wamp.Client, :__publish_error__, [{request, details, uri}, state])

                {:noreply, state}
            end

            @impl true
            def handle_info([@error, @call, request, %{}, uri], state) do
                handle_info([@error, @call, request, %{}, uri, [], %{}], state)
            end

            @impl true
            def handle_info([@error, @call, request, %{}, uri, args], state) do
                handle_info([@error, @call, request, %{}, uri, args, %{}], state)
            end

            @impl true
            def handle_info([@error, @call, request, %{}, uri, args, kwargs], state) do

                state =
                    apply(Wamp.Client, :__call_error__, [{request, uri, args, kwargs}, state])

                {:noreply, state}
            end

            @impl true
            def handle_info({ref, {:ok, :yielded}}, state) do
                {:noreply, state}
            end

            @impl true
            def handle_info({:DOWN, ref, :process, _object, _reason}, state) do
                state =
                    apply(Wamp.Client, :__down__, [ref, state])

                {:noreply, state}
            end

            @impl true
            def handle_info(_, state) do
                {:noreply, state}
            end

            def state(section \\ nil) 
            when is_nil(section) or is_atom(section) do
                GenServer.call(__MODULE__, {:state, section})
            end

            def subscriptions() do
                GenServer.call(__MODULE__, :subscriptions)
            end

            def call(uri, args) 
            when is_list(args) and is_binary(uri) do
                call(uri, args, %{})
            end

            def call(uri, kwargs) 
            when is_map(kwargs) and is_binary(uri) do
                call(uri, [], kwargs)
            end

            def call(uri, args, kwargs) 
            when is_binary(uri) and is_list(args) and is_map(kwargs) do
                GenServer.call(__MODULE__, {@call, %{}, uri, args, kwargs})
            end

            def subscribe(topic, opts \\ %{}) when is_binary(topic) do
                GenServer.call(__MODULE__, {@subscribe, opts, topic})
            end

            def publish(topic, args) do
                publish(topic, args, %{}, %{})
            end

            def publish(topic, args, kwargs) do
                publish(topic, args, kwargs, %{})
            end

            def publish(topic, args, kwargs, opts) 
            when is_binary(topic) and is_list(args) and is_map(kwargs) and is_map(opts) do
                opts = Map.delete(opts, "acknowledge")
                GenServer.call(__MODULE__, {@publish, opts, topic, args, kwargs})
            end

            def ack_publish(topic, args) do
                ack_publish(topic, args, %{}, %{})
            end

            def ack_publish(topic, args, kwargs) do
                ack_publish(topic, args, kwargs, %{})
            end

            def ack_publish(topic, args, kwargs, opts) 
            when is_binary(topic) and is_list(args) and is_map(kwargs) and is_map(opts) do
                opts = Map.put(opts, "acknowledge", true)
                reqid = 
                    GenServer.call(__MODULE__, {@publish, opts, topic, args, kwargs})
                await_acknowledgment(reqid)
            end

            defp await_acknowledgment(reqid) do
                case GenServer.call(__MODULE__, {:event_status, reqid}) do
                    :pending ->
                        await_acknowledgment(reqid)

                    :published ->
                        GenServer.call(__MODULE__, {:publication, reqid})

                    :error ->
                        GenServer.call(__MODULE__, {:publication, reqid})

                    error ->
                        error
                end
            end

            def unsubscribe(topic) when is_binary(topic) do
                GenServer.call(__MODULE__, {@unsubscribe, topic})
            end

            def register(uri, {module, function} = proc, opts \\%{}) 
            when is_atom(module) and is_atom(function) do
                GenServer.call(__MODULE__, {@register, opts, uri,proc})
            end

            def unregister(uri) do
                GenServer.call(__MODULE__, {@unregister, uri})
            end

            def registered(uri) when is_binary(uri) do
                GenServer.call(__MODULE__, {:registered, uri})
            end

            def subscribed(topic) when is_binary(topic) do
                GenServer.call(__MODULE__, {:subscribed, topic})
            end


            def yield(reqid) when is_integer(reqid) do
                GenServer.call(__MODULE__, {:result, reqid})
            end

            def yielded(reqid) when is_integer(reqid) do
                case GenServer.call(__MODULE__, {:call_status, reqid}) do
                    :yielded ->
                        true

                    :error ->
                        true

                    :pending ->
                        false

                    error ->
                        error
                end
            end

            def await(reqid) when is_integer(reqid) do
                case yielded(reqid) do
                    true ->
                        yield(reqid)

                    false ->
                        await(reqid)

                    error ->
                        error
                end
            end

        end
    end

    @doc """
    Registers a procedure to be automatically registered when the client connects.

    The function must accept `(args, kwargs, details)` as arguments and return
    the result value.

    ## Example

        procedure "com.example.add", MyApp.Math, :add
    """
    defmacro procedure(uri, module, fun) do
        module = tear_alias(module)
        quote do
            @procedures {unquote(uri), unquote(module), unquote(fun)}
        end
    end

    @doc """
    Subscribes to a topic channel that is automatically subscribed when the
    client connects. The subscriber module must `use Wamp.Subscriber`.

    ## Example

        channel "events.chat", MyApp.ChatSubscriber
    """
    defmacro channel(uri, module) do
        module = tear_alias(module)
        quote do
            @channels {unquote(uri), unquote(module)}
        end
    end

    @doc false
    defmacro __before_compile__(_env) do

        quote do

            defp __channels__, do: @channels

            defp __procedures__, do: @procedures

        end

    end

    defp tear_alias({:__aliases__, meta, [h|t]}) do
        alias = {:__aliases__, meta, [h]}
        quote do
            Module.concat([unquote(alias)|unquote(t)])
        end
    end

    defp tear_alias(other), do: other

    @doc false
    def __welcome__({sid, details}, {procedures, channels}, state) do

        state = 
            state
            |> Map.update!(:id, fn _ -> sid end)
            |> Map.update!(:status, fn _ -> :connected end)
            |> Map.update!(:details, fn _ ->  details end)

        state = 
            procedures
            |> Enum.reduce(state, fn {uri, module, fun}, state -> 
                procedure = {uri, %{}, {module, fun}}
                {_, state} = __handle_register__(procedure, state)
                state
            end)

        state =
            channels
            |> Enum.reduce(state, fn {uri, subscriber}, state -> 
                topic = {uri, %{}, subscriber}
                {_, state} = __handle_subscribe__(topic, state)
                state
            end)

        state
    end

    @doc false
    def __await__(client, request, current, next) do
        case GenServer.call(client, {next, request}) do
            {^current, _} ->
                __await__(client, request, current, next)
            result -> result
        end
    end


    @doc false
    def __handle_connect__(state, conn) do
        realm = Map.get(state, :realm)
        roles = Map.get(state, :roles)

        payload = [@hello, realm, roles, conn]
        state = send_request(state, payload)
        {{:ok, state.status}, state}
    end

    @doc false
    def __handle_call__({uri, opts, args, kwargs}, state) do
        { request, state } = next_id(state)

        call = %{
            uri: uri,
            result: nil,
            status: :pending,
            args: args,
            kwargs: kwargs,
            options: opts,
            request: request,
        }

        state = 
            state
            |> Map.update!(:calls, &(&1 ++ [call]))

        state = send_request(state, [@call, request, opts, uri, args, kwargs])

        {request, state}
    end

    @doc false
    def __handle_publish__({topic, opts, args, kwargs}, state) do
        { request, state } = next_id(state)

        state = 
            if Map.get(opts, "acknowledge", false) do
                event = %{
                    args: args,
                    topic: topic,
                    options: opts,
                    kwargs: kwargs,
                    status: :pending,
                    publication: nil,
                    request: request,
                }

                Map.update!(state, :events, &(&1 ++ [event]))
            else
                state
            end

        payload = [@publish, request, opts, topic, args, kwargs]

        state = send_request(state, payload)
        {request, state}
    end

    @doc false
    def __handle_unregister__(uri, state) do
        index = 
            Map.get(state, :procedures)
            |> Enum.find_index(fn proc -> 
                case proc do
                    %{uri: ^uri, status: :registered} ->
                        true
                    _ ->
                        false
                end
            end)

        if is_nil(index) do
            {{:error, "wamp.client.procedure_not_found"}, 
                state}
        else

            { request, state } = next_id(state)

            proc = 
                Map.get(state, :procedures) 
                |> Enum.at(index)
                |> Map.put(:request, request)
                |> Map.put(:status, :canceling)

            update = &List.replace_at(&1, index, proc)

            state = Map.update!(state, :procedures, update)

            state = send_request(state, [@unregister, request, proc.id])
            {{:ok, request}, state}
        end
    end

    @doc false
    def __handle_subscribe__({topic, opts, subscriber}, state) do
        { request, state } = next_id(state)

        sub = %{
            id: nil,
            pid: nil,
            ref: nil,
            topic: topic,
            options: opts,
            request: request,
            status: :pending,
            subscriber: subscriber,
        }

        state = 
            state
            |> Map.update!(:subscriptions, &(&1 ++ [sub]))

        payload = [@subscribe, request, opts, topic]
        state = send_request(state, payload)
        {request, state}
    end

    @doc false
    def __handle_unsubscribe__(topic, state) do
        index = 
            Map.get(state, :subscriptions)
            |> Enum.find_index(fn sub -> 
                case sub do
                    %{topic: ^topic, status: :subscribed } ->
                        true
                    _ ->
                        false
                end
            end)

        if is_nil(index) do
            {
                {:error, "wamp.client.subscription_not_found"}, 
                state}
        else

            { request, state } = next_id(state)

            sub = 
                Map.get(state, :subscriptions) 
                |> Enum.at(index)
                |> Map.put(:request, request)
                |> Map.put(:status, :canceling)

            Process.demonitor(sub.ref)

            update = &Wamp.Enum.replace_item_at(&1, index, sub)

            state = Map.update!(state, :subscriptions, update)
            
            payload = [@unsubscribe, request, sub.id]
            state = send_request(state, payload)
            {{:ok, request}, state}
        end
    end

    @doc false
    def __handle_register__({uri, opts, handler}, state) do
        { request, state } = next_id(state)

        proc = %{
            id: nil,
            uri: uri,
            status: :pending,
            request: request,
            details: opts,
            handler: handler,
        }

        state = 
            state
            |> Map.update!(:procedures, &(&1 ++ [proc]))

        payload = [@register, request, opts, uri]
        state = send_request(state, payload)
        {request, state}
    end

    @doc false
    def __handle_yield__({res, pid}, state) do
        index =
            state
            |> Map.get(:invocations)
            |> Enum.find_index(fn inv -> inv.task === pid end)

        if is_nil(index) do
            {{:error, :invocation_task_not_found}, state}
        else
            inv = state |> Map.get(:invocations) |> Enum.at(index)

            state =
                state
                |> Map.update!(:invocations, fn invs -> 
                    head = Enum.slice(invs, 0, index)
                    tail = Enum.slice(invs, index + 1, length(invs))
                    head ++ tail
                end)

            payload = 
                case res do
                    {:ok, {args, kwargs}} ->
                        [@yield, inv.request, %{}, args, kwargs]

                    {:error, uri, args, kwargs} ->
                        [@error, @invocation, inv.request, %{}, uri, args, kwargs]
                    _ ->
                        :none
                end


            state =
                if is_list(payload) do
                    send_request(state, payload)
                else
                    state
                end

            {{:ok, :yielded}, state}
        end
    end

    @doc false
    def __handle_registered__(uri, state) do
        proc  =
            state
            |> Map.get(:procedures)
            |> Enum.find(fn proc -> proc.uri === uri end)

        registered = 
            if is_nil(proc) do
                false
            else
                case proc do
                    %{status: :registered} ->
                        true

                    %{status: :pending} ->
                        :pending

                    _ ->
                        false
                end
            end

        {registered, state}
    end

    @doc false
    def __handle_subscribed__(topic, state) do
        sub =
            state
            |> Map.get(:subscriptions)
            |> Enum.find(fn sub -> sub.topic === topic end)

        subscribed = 
            if is_nil(sub) do
                false
            else
                case sub do
                    %{status: :subscribed} ->
                        true

                    %{status: :pending} ->
                        :pending

                    _ ->
                        false
                end
            end
        {subscribed, state}
    end

    @doc false
    def __handle_call_status__(request, state) do
        call =
            state
            |> Map.get(:calls)
            |> Enum.find(fn call -> call.request === request end)

        status = 
            if is_nil(call) do
                {:error, :call_not_found}
            else
                call.status
            end

        {status, state}
    end

    @doc false
    def __handle_event_status__(request, state) do
        event =
            state
            |> Map.get(:events)
            |> Enum.find(fn e -> e.request === request end)

        status = 
            if is_nil(event) do
                {:error, :call_not_found}
            else
                event.status
            end

        {status, state}
    end

    @doc false
    def __handle_yield_publication__(request, state) do
        index =
            state
            |> Map.get(:events)
            |> Enum.find_index(fn e -> e.request === request end)

        if is_nil(index) do
            {{:error, :event_not_found}, state}
        else
            event = 
                state
                |> Map.get(:events) 
                |> Enum.at(index)

            publication = 
                case event do
                    %{status: :published} ->
                        {:ok, event.publication}

                    %{status: :error} ->
                        {:error, event.publication}

                    _ ->   
                        nil
                end

            state =
                state
                |> Map.update!(:events, &List.delete_at(&1, index))

            {publication, state}
        end

    end

    @doc false
    def __handle_yield_result__(request, state) do
        index =
            state
            |> Map.get(:calls)
            |> Enum.find_index(fn call -> call.request === request end)

        if is_nil(index) do
            {{:error, :call_not_found}, state}
        else
            %{result: result} = 
                state
                |> Map.get(:calls) 
                |> Enum.at(index)

            state =
                state
                |> Map.update!(:calls, &List.delete_at(&1, index))

            {result, state}
        end

    end

    @doc false
    def __handle_goodbye__(reason, state) do
        state = 
            state
            |> Map.update!(:id, fn _ -> nil end)
            |> Map.update!(:status, fn _ -> :disconnected end)
            |> Map.update!(:calls, fn _ -> [] end)
            |> Map.update!(:details, fn _ -> nil end)
            |> Map.update!(:procedures, fn _ -> [] end)
            |> Map.update!(:subscriptions, fn _ -> [] end)

        payload = [@goodbye, %{}, reason]

        {{:ok, :disconnected}, send_request(state, payload)}
    end

    @doc false
    def __challenge__(state) do
        reason = "wamp.error.cannot_authenticate"
        payload = [@abort, %{}, reason]
        {reason, send_request(state, payload)}
    end

    @doc false
    def __goodbye__(state) do
        uri = "wamp.close.goodbye_and_out"
        payload = [@goodbye, %{}, uri]
        {uri, send_request(state, payload)}
    end

    @doc false
    def __published__({request, pubid}, state) do
        index =
            state
            |> Map.get(:events)
            |> Enum.find_index(fn e -> e.request === request end)

        if is_nil(index) do
            state
        else
            event = 
                state
                |> Map.get(:events) 
                |> Enum.at(index)
                |> Map.put(:status, :published)
                |> Map.put(:publication, pubid)

            update = &Wamp.Enum.replace_item_at(&1, index, event)

            Map.update!(state, :events, update)
        end
    end

    @doc false
    def __subscribed__({request, subid}, state) do
        index = 
            Map.get(state, :subscriptions)
            |> Enum.find_index(fn sub -> 
                case sub.status do
                    {:pending, ^request} ->
                        true
                    _ ->
                        false
                end
            end)

        if is_nil(index) do
            state
        else

            sub = 
                Map.get(state, :subscriptions) 
                |> Enum.at(index)
                |> Map.put(:id, subid)
                |> Map.put(:status, :subscribed)

            args = [
                id: sub.id,
                realm: state.realm,
                subscriber: sub.subscriber
            ]

            with {:ok, pid} <- Wamp.Subscriber.start_link(args) do

                sub = 
                    sub
                    |> Map.update!(:pid, fn _ -> pid end)
                    |> Map.update!(:ref, fn _ -> Process.monitor(pid) end)

                update = &Wamp.Enum.replace_item_at(&1, index, sub)

                Map.update!(state, :subscriptions, update)

            else
                _ -> 
                    state
            end
        end
    end

    @doc false
    def __down__(ref, state) do
        index = 
            Map.get(state, :subscriptions)
            |> Enum.find_index(fn 
                %{ref: ^ref} -> true
                    _ -> false
            end)


        if is_nil(index) do
            state
        else
            sub = 
                state
                |> Map.get(:subscriptions)
                |> Enum.at(index)

            case sub.status do
                :pending ->
                    # imposible for this condition to hold true "i think"
                    Map.update!(state, :subscriptions, fn subs -> 
                        List.delete_at(subs, index)
                    end)

                :subscribed ->
                    {_, state} =
                        __handle_unsubscribe__(sub.topic, state)
                    state

                _ ->
                    state
            end
        end
    end

    @doc false
    def __call_error__({request, uri, args, kwargs}, state) do
        index = 
            state
            |> Map.get(:calls)
            |> Enum.find_index(fn call -> call.request === request end)

        if is_nil(index) do
            state
        else
            call = 
                state
                |> Map.get(:calls)
                |> Enum.at(index)
                |> Map.put(:status, :error)
                |> Map.put(:result, {:error, {uri, args, kwargs}})

            update = &Wamp.Enum.replace_item_at(&1, index, call)

            Map.update!(state, :calls, update)
        end
    end

    @doc false
    def __publish_error__({request, details, uri}, state) do
        index =
            state
            |> Map.get(:events)
            |> Enum.find_index(fn e -> e.request === request end)

        if is_nil(index) do
            state
        else
            event = 
                state
                |> Map.get(:events) 
                |> Enum.at(index)
                |> Map.put(:status, :error)
                |> Map.put(:publication, {uri, details})

            update = &Wamp.Enum.replace_item_at(&1, index, event)
            Map.update!(state, :events, update)
        end
    end

    @doc false
    def __subscribe_error__({request, _details, uri}, state) do
        index = 
            Map.get(state, :subscriptions)
            |> Enum.find_index(fn sub -> 
                case sub do
                    %{status: :pending, request: ^request} ->
                        true
                    _ -> 
                        false
                end
            end)

        if is_nil(index) do
            state
        else
            sub = 
                Map.get(state, :subscriptions) 
                |> Enum.at(index)
                |> Map.put(:status, {:error, uri})

            update = &Wamp.Enum.replace_item_at(&1, index, sub)

            Map.update!(state, :subscriptions, update)
        end
    end

    @doc false
    def __register_error__({request, _details, uri}, state) do
        index = 
            Map.get(state, :procedures)
            |> Enum.find_index(fn proc -> 
                case proc do
                    %{status: :pending, request: ^request} ->
                        true
                    _ ->
                        false
                end
            end)

        if is_nil(index) do
            state
        else
            proc = 
                Map.get(state, :procedures) 
                |> Enum.at(index)
                |> Map.put(:status, {:error, uri})

            Map.update!(state, :procedures, &List.replace_at(&1, index, proc))
        end
    end

    @doc false
    def __interrupt__({req, _details}, state) do
        index =
            state
            |> Map.get(:invocations)
            |> Enum.find_index(fn inv -> 
                case inv.task do
                    %{request: ^req} -> 
                        true
                    _ -> 
                        false
                end
            end)

        if is_nil(index) do
            state
        else
    
            inv = 
                state 
                |> Map.get(:invocations) 
                |> Enum.at(index)

            if Process.alive?(inv.pid) do
                Process.exit(inv.pid, :kill)
            end

            Map.update!(state, :invocations, fn invs -> 
                Wamp.Enum.remove_item_at(invs, index)
            end)
        end
    end

    @doc false
    def __invocation__(client, {req, id, details, args, kwargs}, state) do
        proc = 
            Map.get(state, :procedures)
            |> Enum.find(fn proc -> 
                case proc do
                    %{id: ^id, status: :registered }->
                        true
                    _ ->
                        false
                end
            end)

        if is_nil(proc) do
            state
        else

            %{uri: uri} = proc

            task_args = [client, proc, details, args, kwargs]

            {:ok, task} = 
                Task.start(Wamp.Client, :invoke, task_args)

            inv = %{
                uri: uri,
                task: task,
                args: args,
                kwargs: kwargs,
                request: req,
                details: details,
            }

            state
            |> Map.update!(:invocations, &(&1 ++ [inv]))
        end
    end

    @doc false
    def __event__({subid, pubid, details, args, kwargs}, state) do
        index = 
            state
            |> Map.get(:subscriptions) 
            |> Enum.find_index(fn sub -> sub.id === subid end)

        if is_nil(index) do
            state
        else
            sub = 
                state
                |> Map.get(:subscriptions) 
                |> Enum.at(index)

            handle_event({pubid, details, args, kwargs}, sub)
            state
        end
    end

    @doc false
    def __unsubscribed__({subid, reason}, state) do
        index = 
            state
            |> Map.get(:subscriptions)
            |> Enum.find_index(fn sub -> sub.id === subid end)


        if is_nil(index) do
            state
        else

            sub = 
                state 
                |> Map.get(:subscriptions) 
                |> Enum.at(index)

            Process.exit(sub.pid, reason)

            Map.update!(state, :subscriptions, fn subs -> 
                List.delete_at(subs, index)
            end)

        end
    end

    @doc false
    def __unsubscribed__(request, state) do
        index = 
            Map.get(state, :subscriptions)
            |> Enum.find_index(fn sub -> 
                case sub do
                    %{status: :canceling, request: ^request} ->
                        true
                    _ -> false
                end
            end)

        if is_nil(index) do
            state
        else
            Map.update!(state, :subscriptions, fn subs -> 
                List.delete_at(subs, index)
            end)
        end
    end

    @doc false
    def __registered__({request, regid}, state) do
        index = 
            Map.get(state, :procedures)
            |> Enum.find_index(fn proc -> 
                case proc do
                    %{status: :pending, request: ^request} ->
                        true
                    _ ->
                        false
                end
            end)

        if is_nil(index) do
            state
        else
            proc = 
                Map.get(state, :procedures) 
                |> Enum.at(index)
                |> Map.put(:id, regid)
                |> Map.put(:status, :registered)

            Map.update!(state, :procedures, &List.replace_at(&1, index, proc))
        end
    end

    @doc false
    def __unregistered__({regid, _reason}, state) do
        index = 
            state
            |> Map.get(:procedures)
            |> Enum.find_index(fn proc -> proc.id === regid end)


        if is_nil(index) do
            state
        else

            _proc = 
                state 
                |> Map.get(:procedures) 
                |> Enum.at(index)

            Map.update!(state, :procedures, &List.delete_at(&1, index))
        end
    end

    @doc false
    def __unregistered__(request, state) when is_integer(request) do
        index = 
            Map.get(state, :procedures)
            |> Enum.find_index(fn proc -> 
                case proc do
                    %{status: :canceling, request: ^request} ->
                        true
                    _ -> 
                        false
                end
            end)

        if is_nil(index) do
            state
        else

            _proc = 
                Map.get(state, :procedures) 
                |> Enum.at(index)

            Map.update!(state, :procedures, &List.delete_at(&1, index))
        end
    end

    @doc false
    def __result__({request, _details, args, kwargs}, state) do
        index =
            state
            |> Map.get(:calls)
            |> Enum.find_index(fn call -> call.request === request end)

        if is_nil(index) do
            state
        else
            call = 
                state
                |> Map.get(:calls) 
                |> Enum.at(index)
                |> Map.put(:status, :yielded)
                |> Map.put(:result, {:ok, {args, kwargs}})

            Map.update!(state, :calls, &List.replace_at(&1, index, call))
        end
    end

    @doc false
    def invoke(client, proc, details, args, kwargs) do

        {module, fun} = proc.handler

        response = 
            try do
                case apply(module, fun, [args, kwargs, details]) do
                    {:ok, args} when is_list(args) -> 
                          {:ok, {args, %{}}}

                    {:ok, args, kwargs} when is_list(args) and is_map(kwargs) -> 
                          {:ok, {args, kwargs}}

                    {:ok, args} -> 
                          {:ok, {List.wrap(args), kwargs}}

                    {:error, uri} when is_binary(uri) ->
                          {:error, uri, [], %{}}

                    {:error, uri, args} when is_binary(uri) and is_list(args) ->
                          {:error, uri, args, %{}}

                    {:error, uri, args, kwargs} when is_binary(uri) and is_list(args) and is_map(kwargs) ->
                          {:error, uri, args, kwargs}
                end
            rescue
                error in Wamp.Client.InvocationError ->
                    {:error, error.uri, error.args, error.kwargs} 

                exception -> 
                    message = Exception.message(exception)
                    {:error, "wamp.invocation.error", [message], %{}}
            end

        GenServer.call(client, {@yield, response})
    end

    defp next_id(state) do
        id = Map.get(state, :next_id)
        { id, Map.update!(state, :next_id, &(&1 + 1)) }
    end

    defp send_request(state, payload) when is_list(payload) do
        send(state.router, {payload, state.pid})
        state
    end

    defp handle_event({pubid, details, args, kwargs}, sub) do
        send(sub.pid, {@event, pubid, details, args, kwargs})
    end

end
