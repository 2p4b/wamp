defmodule Wamp.Router do

    @version "0.1.0"

    use Wamp.Spec

    defmacro __using__(opts) do

        otp_app = Keyword.get(opts, :otp_app)
        dealer = Keyword.get(opts, :dealer, Wamp.Example.Dealer)
        broker = Keyword.get(opts, :broker, Wamp.Example.Broker)

        quote do

            @version "0.1.0"

            @otp_app unquote(otp_app)

            @dealer unquote(tear_alias(dealer))

            @broker unquote(tear_alias(broker))

            use Wamp.Spec

            use GenServer

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


            def start_link(opts) when is_nil(opts) or is_list(opts) do
                config =
                    if is_nil(opts) do
                        get_env()
                    else
                        opts ++ get_env()
                    end

                if not Keyword.has_key?(config, :realm) do
                    raise "Must specify realm for router"
                end

                GenServer.start_link(__MODULE__, config, name: __MODULE__)
            end

            @impl true
            def init(config) do

                realm = Keyword.get(config, :realm)

                args = [
                    realm: realm, 
                    router: self(), 
                    broker: @broker,
                    dealer: @dealer
                ]

                children = [
                    {Wamp.PubSub.Broker, args}, 
                    {Wamp.RPC.Dealer, args}
                ]

                Supervisor.start_link(children, strategy: :one_for_all)

                {:ok, 
                    %{ 
                        realm: realm,
                        sessions: [], 
                        broker: Process.whereis(Wamp.Router.broker_name(realm)),
                        dealer: Process.whereis(Wamp.Router.dealer_name(realm)),
                        session_count: 0,
                        req_count: 0, 
                    } 
                }
            end


            @impl true
            def handle_info({[@register, req, options, uri], from}, state) do
                args = [[req, options, uri], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__register__, args)}
            end

            @impl true
            def handle_info({[@unregister, req, regid], from}, state) do
                args = [[req, regid], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__unregister__, args)}
            end

            @impl true
            def handle_info({[@call, req, options, uri], from}, state) do
                handle_info({[@call, req, options, uri, [], %{}], from}, state)
            end

            @impl true
            def handle_info({[@call, req, options, uri, args], from}, state) do
                handle_info({[@call, req, options, uri, args, %{}], from}, state)
            end

            @impl true
            def handle_info({[@call, req, opts, uri, args, kwargs], from}, state) do
                args = [[req, opts, uri, args, kwargs], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__call__, args)}
            end

            @impl true
            def handle_info({[@yield, req, options, args], from}, state) do
                handle_info({[@yield, req, options, args, %{}], from}, state)
            end

            @impl true
            def handle_info({[@yield, req, options, args, kwargs], from}, state) do
                args = [[req, options, args, kwargs], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__yield__, args)}
            end

            @impl true
            def handle_info({[@error, @invocation, req, opts, error], from}, state) do
                handle_info({[@error, @invocation, req, opts, error, [], %{}], from}, state)
            end

            @impl true
            def handle_info({[@error, @invocation, req, opts, error, args], from}, state) do
                handle_info({[@error, @invocation, req, opts, error, args, %{}], from}, state)
            end

            @impl true
            def handle_info({[@error, @invocation, req, opts, error, args, kwargs], from}, state) do
                args = [[@invocation, req, opts, error, args, kwargs], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__error__, args)}
            end

            @impl true
            def handle_info({[@cancel, req, opts], from}, state) do
                args = [[req, opts], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__error__, args)}
            end

            @impl true
            def handle_info({[@hello, realm, details], from}, state) do
                handle_info({[@hello, realm, details, :elixir], from}, state)
            end

            @impl true
            def handle_info({[@hello, realm, opts, conn], from}, state) do
                args = [[realm, opts, conn], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__hello__, args)}
            end

            @impl true
            def handle_info({[@goodbye, opts, reason], from}, state) do
                args = [[opts, reason], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__goodbye__, args)}
            end

            @impl true
            def handle_info({[@subscribe, req, opts, topic], from}, state) 
            when is_binary(topic) do
                args = [[req, opts, topic], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__subscribe__, args)}
            end

            @impl true
            def handle_info({[@unsubscribe, req, subid], from}, state) do
                args = [[req, subid], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__unsubscribe__, args)}
            end

            @impl true
            def handle_info({[@publish, req, options, topic, args], from}, state) 
            when is_binary(topic) do
                handle_info({[@publish, req, options, topic, args, %{}], from}, state)
            end

            @impl true
            def handle_info({[@publish, req, opts, topic, args, kwargs], from}, state) 
            when is_binary(topic) do
                args = [[req, opts, topic, args, kwargs], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__publish__, args)}
            end

            @impl true
            def handle_info({[@authenticate, challenge, opts], from}, state) do
                args = [[challenge, opts], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__authenticate__, args)}
            end

            @impl true
            def handle_info({[@abort, opts, reason], from}, state) do
                args = [[opts, reason], {__MODULE__, from}, state]
                {:noreply, apply(Wamp.Router, :__abort__, args)}
            end

            @impl true
            def handle_info({:DOWN, ref, :process, _obj, reason}, state) do
                args = [{ref, reason}, state]
                {:noreply, apply(Wamp.Router, :__session_down__, args)}
            end

            @impl true
            def handle_info({:challenge, sid, method, challenge}, state) do
                args = [{method, sid, challenge}, state]
                {:noreply, apply(Wamp.Router, :__challenge__, args)}
            end

            @impl true
            def handle_info({:welcome, sid, auth}, state) do
                args = [{sid, auth}, state]
                {:noreply, apply(Wamp.Router, :__welcome__, args)}
            end

            @impl true
            def handle_info({:push, sid, payload}, state) do
                args = [{sid, payload}, state]
                {:noreply, apply(Wamp.Router, :__push__, args)}
            end

            @impl true
            def handle_info({:push, events}, state) when is_list(events) do
                args = [events, state]
                {:noreply, apply(Wamp.Router, :__push__, args)}
            end

            @impl true
            def handle_info({:abort, sid, opts, reason}, state) do
                args = [{sid, opts, reason}, state]
                {:noreply, apply(Wamp.Router, :__terminate__, args)}
            end

            @impl true
            def handle_info({_ref, _task_return}, state) do
                {:noreply, state}
            end

            @impl true
            def handle_call({:nextid, sid}, _from, state) do

                index = 
                    Map.get(state, :sessions)
                    |> Enum.find_index(fn 
                        %{id: ^sid} -> true 
                        _ -> false 
                    end)

                if not is_nil(index) do

                    session = 
                        Map.get(state, :sessions)
                        |> Enum.at(index)

                    state = 
                        Map.update!(state, :sessions, fn sessions -> 
                            head = Enum.slice(sessions, 0, index)    
                            tail = Enum.slice(sessions, index + 1, length(sessions))
                            head ++ [ Map.update!(session, :next_id, &(&1 +1)) ] ++ tail
                        end)

                    {:reply, {:ok, Map.get(session, :next_id)}, state}
                else
                    {:reply, {:error, "session.not_found"} ,state}
                end

            end

            @impl true
            def handle_call(:state, _from, state) do
                {:reply, state, state}
            end

            @impl true
            def handle_call({:get, prop}, _from, state) when is_atom(prop) do
                {:reply, Map.get(state, prop), state}
            end

            @impl true
            def handle_call(_unknown, _from, state) do
                {:reply, :error, state}
            end

            def challenge(%{id: sid}) do
                {:anonymous, %{
                    authid: sid,
                    authrole: :anonymous,
                    authmethod: :anonymous,
                    authprovider: :static,
                    authextra: %{}
                }}
            end

            def check_challenge({method, challenge}, {token, details}, session) do
                {:error, "authentication.error"}
            end

            def send(message) when is_list(message) do
                send(__MODULE__, {message, self()}) 
            end

            def get(prop) when is_atom(prop) do
                GenServer.call(__MODULE__, {:get, prop})
            end

            def state(prop\\ nil) when is_nil(prop) or is_atom(prop) do 
                GenServer.call(__MODULE__, :state)
            end

            def subscriptions(topic \\ nil) do
                broker = get(:broker)
                if is_nil(topic) do
                    GenServer.call(broker, {:get, :subscriptions})
                else
                    GenServer.call(broker, {:subscriptions, topic})
                end
            end

            def procedures(uri \\ nil) do
                dealer = get(:dealer)
                if is_nil(uri) do
                    GenServer.call(dealer, {:get, :procedures})
                else
                    GenServer.call(dealer, {:procedures, uri})
                end
            end

            def invocations() do
                dealer = get(:dealer)
                GenServer.call(dealer, {:get, :invocations})
            end

            def revoke_subscription(id, reason \\ "") 
            when is_integer(id) and is_binary(reason) do
                broker = get(:broker)
                GenServer.call(broker, {:revoke, id, reason})
            end

            def revoke_registration(id, reason \\ "") 
            when is_integer(id) and is_binary(reason) do
                dealer = get(:dealer)
                GenServer.call(dealer, {:revoke, id, reason})
            end


            defoverridable challenge: 1

            defoverridable check_challenge: 3

        end

    end

    defp tear_alias({:__aliases__, meta, [h|t]}) do
        alias = {:__aliases__, meta, [h]}
        quote do
            Module.concat([unquote(alias)|unquote(t)])
        end
    end

    defp tear_alias(other), do: other

    def dealer_name(realm) when is_binary(realm) do
        "wamp." <> realm <> ".dealer"
        |> String.to_atom()
    end

    def broker_name(realm) when is_binary(realm) do
        "wamp." <> realm <> ".broker"
        |> String.to_atom()
    end

    def __hello__([realm, details, conn], {router, from}, state) do
        with {:ok, session} <- fetch_session(state, from) do
            send(session.pid, protocol_violation())
            disconnect(state, session)
        else
            _ ->

                if realm === state.realm do

                    { session, state } = 
                        create_session({from, details, conn}, state)

                    Task.start(__MODULE__, :__authorize__, [session, router])

                    Map.update!(state, :sessions, fn sessions -> 
                        sessions ++ [ session ]
                    end)

                else
                    send(from, protocol_violation())
                    state
                end
        end
    end

    def __authorize__(%{id: sid} = session, router) do
        case apply(router, :challenge, [session]) do
            {:anonymous, %{authid: _, authrole: _, authmethod: :anonymous, authprovider: _} = details} ->
                send(router, {:welcome, sid, details})

            {:scram, details} ->
                send(router, {:challenge, sid, :scram, details})

            {:ticket, details} ->
                send(router, {:challenge, sid, :ticket,  details})

            {:wampcra, details} ->
                send(router, {:challenge, sid, :wampcra, details})

            _ ->
                uri = "wamp.authentication.failed"
                send(router, {:abort, sid, %{}, uri})
        end
    end

    def __authenticate__([token, details], {router, from}, state) do
        case fetch_session(state, from) do

            {:ok, %{challenge: _} = session} ->
                args = [router, {token, details}, session]
                Task.start(__MODULE__, :__check_challenge__, args)
                state

            {:ok, session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state
        end

    end

    def __check_challenge__(router, answer, session) do

        {challenge, session} = 
            Map.pop(session, :challenge)

        {authmethod, _} = challenge

        args = [challenge, answer, session]

        case apply(router, :check_challenge, args) do
            {:ok, %{authmethod: ^authmethod, authid: _, authprovider: _, authrole: _} = details} ->
                send(router, {:welcome, session.id, details})

            {:error, uri} ->
                send(router, {:abort, session.id, %{}, uri})

            _ ->
                uri = "wamp.authentication.failed"
                send(router, {:abort, session.id, %{}, uri})
        end

    end

    def __subscribe__([req, opts, topic], {_, from}, state) do
        case fetch_authorized_session(state, from) do

            {:ok, session} ->
                send(state.broker, {[@subscribe, req, opts, topic], session})
                state

            {:error, session: %{} = session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state
        end
    end

    def __publish__([req, opts, topic, args, kwargs], {_, from}, state) do
        case fetch_authorized_session(state, from) do

            {:ok, session} ->
                send(state.broker, {[@publish, req, opts, topic, args, kwargs], session})
                state

            {:error, session: %{} = session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state
        end
    end

    def __unsubscribe__([req, subid], {_, from}, state) do
        case fetch_authorized_session(state, from) do

            {:ok, session} ->
                send(state.broker, {[@unsubscribe, req, subid], session})
                state

            {:error, session: %{} = session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state
        end
    end

    def __register__([req, options, uri], {_, from}, state) do
        case fetch_authorized_session(state, from) do
            {:ok, session} ->
                send(state.dealer, {[@register, req, options, uri], session})
                state

            {:error, session: %{} = session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state

        end
    end

    def __unregister__([req, regid], {_, from}, state) do
        case fetch_authorized_session(state, from) do
            {:ok, session} ->
                send(state.dealer, {[@unregistered, req, regid], session})
                state

            {:error, session: %{} = session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state

        end
    end

    def __call__([req, options, uri, args, kwargs], {_, from}, state) do
        case fetch_authorized_session(state, from) do
            {:ok, session} ->
                send(state.dealer, {[@call, req, options, uri, args, kwargs], session})
                state

            {:error, session: %{} = session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state

        end
    end

    def __yield__([req, options, args, kwargs], {_, from}, state) do
        case fetch_authorized_session(state, from) do
            {:ok, session} ->
                send(state.dealer, {[@yield, req, options, args, kwargs], session})
                state

            {:error, session: %{} = session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state

        end
    end

    def __cancel__([req, options], {_, from}, state) do
        case fetch_authorized_session(state, from) do
            {:ok, session} ->
                send(state.dealer, {[@cancel, req, options], session})
                state

            {:error, session: %{} = session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state
        end
    end

    def __error__([@invocation, req, otps, uri, args, kwargs], {_, from}, state) do
        case fetch_authorized_session(state, from) do
            {:ok, session} ->
                send(state.dealer, {[@error, @invocation, req, otps, uri, args, kwargs], session})
                state

            {:error, session: %{} = session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state
        end
    end

    def __goodbye__([_details, _reason], {_, from}, state) do
        case fetch_authorized_session(state, from) do

            {:ok, session} ->
                send(session.pid, goodbye_and_out())
                disconnect(state, session)

            {:error, session: %{} = session} ->
                send(session.pid, protocol_violation())
                disconnect(state, session)

            _ ->
                state
        end
    end

    def __abort__([_details, _reason], {_, from}, state) do
        session = get_session(state, from)

        if is_nil(session) do
            state
        else
            disconnect(state, session)
        end
    end

    def __session_down__({ref, _reason}, state) do
        session = 
            Map.get(state, :sessions)
            |> Enum.find(fn 
                %{ref: ^ref} -> true
                    _ -> false
            end)

        if is_nil(session) do
            state
        else
            disconnect(state, session)
        end
    end

    def __challenge__({method, sid, challenge}, state) do

        index = 
            Map.get(state, :sessions)
            |> Enum.find_index(fn 
                %{id: ^sid, auth: nil} -> true
                    _ -> false
            end)

        if is_nil(index) do
            state
        else

            session = 
                state 
                |> Map.get(:sessions) 
                |> Enum.at(index)
                |> Map.put(:challenge, {method, challenge})

            with %{pid: pid} <- session do
                method = 
                    if method === :scram do
                        "wamp-scram"
                    else
                        method
                    end
                send(pid, [@challenge, method, challenge])
            end

            update = &Wamp.Enum.replace_item_at(&1, index, session)

            Map.update!(state, :sessions, update)
        end
    end

    def __welcome__({sid, auth}, state) do

        index = 
            Map.get(state, :sessions)
            |> Enum.find_index(fn 
                %{id: ^sid, auth: nil} -> true
                    _ -> false
            end)

        if is_nil(index) do
            state
        else

            session = 
                state 
                |> Map.get(:sessions) 
                |> Enum.at(index)
                |> Map.delete(:challenge)
                |> Map.put(:auth, auth)
                |> Map.put(:authorized, true)


            with %{pid: pid} <- session do

                handle = {:features, session}

                broker_features = GenServer.call(state.broker, handle)

                dealer_features = GenServer.call(state.dealer, handle)

                details = %{
                    "realm" => state.realm,
                    "agent" => "wamp-" <> @version,
                    "roles" => %{
                        "broker" => %{
                            "features" => broker_features
                        },
                        "dealer" => %{
                            "features" => dealer_features
                        }
                    }
                }

                send(pid, [@welcome, sid, Map.merge(auth, details)])
            end

            update = &Wamp.Enum.replace_item_at(&1, index, session)

            Map.update!(state, :sessions, update)
        end
    end

    def __push__({sid, payload}, state) do

        session = 
            Map.get(state, :sessions)
            |> Enum.find(fn 
                %{id: ^sid} -> true
                    _ -> false
            end)

        with %{pid: pid} <- session do
            send(pid, payload)
        end

        state
    end

    def __push__(events, state) when is_list(events) do

        Enum.each(events, fn {sid, payload} -> 
            __push__({sid, payload}, state)
        end)

        state
    end

    def __terminate__({sid, details, reason}, state) do
        session = 
            Map.get(state, :sessions)
            |> Enum.find(fn 
                %{id: ^sid} -> true
                  _ -> false
            end)

        if is_nil(session) do
            state
        else
            send(session.pid, [@abort, details, reason])
            disconnect(state, session)
        end
    end

    defp disconnect(state, session) do

        %{id: sid, ref: ref, pid: pid} = session

        if Process.alive?(pid) do
            Process.demonitor(ref)
        end

        send(state.broker, {:disconnected, session})
        send(state.dealer, {:disconnected, session})

        Map.update!(state, :sessions, fn sessions -> 
            Enum.filter(sessions, fn 
                %{id: ^sid} -> false
                _ -> true
            end)
        end)

    end

    defp get_session(state, sid) when is_integer(sid)  do
        Map.get(state, :sessions)
        |> Enum.find(fn 
            %{id: ^sid} -> true
              _ -> false
        end)
    end

    defp get_session(state, pid) when is_pid(pid)  do
        Map.get(state, :sessions)
        |> Enum.find(fn 
            %{pid: ^pid} -> true
                _ -> false
        end)
    end

    defp fetch_session(state, id) do

        session = get_session(state, id)

        if is_nil(session) do
            {:error, :no_found}
        else
            {:ok, session}
        end
    end

    defp fetch_authorized_session(state, id) do

        session = get_session(state, id)

        case session do 

            %{auth: %{}} ->
                {:ok, session}

            %{auth: nil} ->
                {:error, session}

            _ ->
                {:error, :not_found}
        end
    end


    defp create_session({pid, details, conn}, state) do

        { id, state } = state 
                         |> increament(:session_count)

        ref = Process.monitor(pid)

        timestamp = DateTime.utc_now()

        session = %{
            id: id, 
            ref: ref,
            pid: pid, 
            auth: nil,
            next_id: 1,
            conn: conn,
            details: details,
            created_at: timestamp,
        }

        { session, state }
    end

    defp protocol_violation() do
        [@abort, %{}, "wamp.error.protocol_violation"]
    end

    defp goodbye_and_out() do
        [@goodbye, %{}, "wamp.close.goodbye_and_out"]
    end

    defp increament(state, prop) when is_atom(prop) do
        state = Map.update!(state, prop, &(&1 + 1))
        { Map.get(state, prop), state }
    end

end
