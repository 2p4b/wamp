defmodule Wamp.RPC.Dealer do
    @moduledoc """
    GenServer that manages remote procedure call routing within a WAMP realm.

    The dealer handles procedure registration, invocation routing, result
    forwarding, and call cancellation. It is started automatically by the router.

    ## Features

      * Caller identification (`disclose_me`)
      * Call cancellation with modes: `"skip"`, `"kill"`, `"killnowait"`
      * Shared procedure registration
      * Registration revocation (server-initiated)
      * Progressive call results
      * Session, registration, and testament meta APIs

    ## Custom Dealer

    The procedure registration approval and invocation routing logic is delegated
    to a custom dealer module that implements the `Wamp.Spec.Dealer` behaviour.
    The dealer module's `procedure/3` callback selects which registered callee
    should handle a given call. See `Wamp.Example.Dealer` for a reference
    implementation.
    """

    use Wamp.Spec

    use GenServer

    defstruct [
        :pid,
        :realm,
        :router,
        :dealer,
        next_id: 1,
        procedures: [],
        invocations: [],
        publication_count: 0,
    ]

    @doc """
    Returns the dealer feature flags as a map.
    """
    def features(_session) do
        %{
            "call_canceling" => true,
            "session_meta_api" => true,
            "testament_meta_api" => true,
            "shared_registration" => true,
            "payload_transparency" => true,
            "caller_identification" => true,
            "registration_meta_api" => true,
            "registration_revocation" => true,
            "progressive_call_results" => true,
            "pattern_based_registration" => false,
            "payload_encryption_cryptobox" => false
        }
    end

    @doc """
    Starts the dealer process linked to the calling process.

    ## Options

      * `:realm` - (required) the WAMP realm name
      * `:router` - the router PID
      * `:dealer` - the custom dealer module
    """
    def start_link(default) do
        name =
            default
            |> Keyword.get(:realm)
            |> Wamp.Router.dealer_name()
        GenServer.start_link(__MODULE__, default, name: name)
    end

    @impl true
    def init(args) do
        {:ok, 
            %Wamp.RPC.Dealer{ 
                pid: self(),
                next_id: 1,
                procedures: %{},
                invocations: [],
                realm: Keyword.get(args, :realm),
                dealer: Keyword.get(args, :dealer),
                router: Keyword.get(args, :router),
                publication_count: 0,
            }
        }
    end

    @impl true
    def handle_info({[@cancel, request, options], session}, state) do

        %{id: sid} = session

        index =  
            Map.get(state, :invocations)
            |> Enum.find(fn 
                %{caller_sid: ^sid, request: ^request, status: :pending} -> true
                _ -> false
            end)

        state =
            if is_nil(index) do

                error = "wamp.error.call_request_notfound"

                payload = [@error, @cancel, request, %{}, error]

                send(state.router, {:push, sid, payload})

                state
            else

                invocation = 
                    Map.get(state, :invocations)
                    |> Enum.at(index)

                case invocation do

                    %{id: invocation_id, caller_sid: caller_sid, callee_sid: callee_sid} ->


                        interupt = [@interrupt, invocation_id, options]

                        error = [@error, @cancel, request, %{}, "wamp.error.cancelled"]

                        case Map.get(options, "mode") do
                            "skip" ->
                                send(state.router, {:push, caller_sid, error})
                                Map.update!(state, :invocations, fn invs -> 
                                    cancel = &Map.put(&1, :status, :canceled_skip)
                                    List.update_at(invs, index, cancel)
                                end)

                            "kill" ->
                                send(state.router, {:push, callee_sid, interupt})
                                Map.update!(state, :invocations, fn invs -> 
                                    cancel = &Map.put(&1, :status, :canceled_kill)
                                    List.update_at(invs, index, cancel)
                                end)

                            "killnowait" ->
                                send(state.router, {:push, caller_sid, error})
                                send(state.router, {:push, callee_sid, interupt})
                                Map.update!(state, :invocations, fn invs ->
                                    head = Enum.slice(invs, 0, index) 
                                    tail = Enum.slice(invs, index + 1, length(invs))
                                    head ++ tail
                                end)

                            _ ->
                                Map.update!(state, :invocations, fn invs -> 
                                    cancel = &Map.put(&1, :status, :canceled)
                                    List.update_at(invs, index, cancel)
                                end)
                        end


                    _ ->
                        code = "wamp.dealer.error"
                        payload = [@error, @cancel, %{}, code]
                        send(state.router, {:push, sid, payload})
                        state
                end

            end
        {:noreply, state}
    end

    @impl true
    def handle_info({[@register, request, opts, uri], session}, state) do
        %{id: sid} = session

        procs = Map.get(state, :procedures) |> Map.get(uri, [])

        proc = 
            procs
            |> Enum.find(fn 
                %{sid: ^sid, uri: ^uri} -> true
                _ -> false
            end)

        state = 
            if is_nil(proc) do

                args = {uri, opts, session}

                Task.start(__MODULE__, :register, [self(), state.dealer, args])

                proc = %Wamp.RPC.Procedure{
                    id: nil, 
                    sid: sid, 
                    uri: uri, 
                    status: :pending,
                    options: opts,
                    request: request,
                    attributes: nil,
                }

                update_procedures(state, uri, procs ++ [proc])

            else
                payload = [
                    @error, @register, 
                    request, %{}, 
                    "wamp.error.proc_duplication"
                ]

                send(state.router, {:push, sid, payload})

                state

            end

        {:noreply, state}

    end

    @impl true
    def handle_info({[@unregister, request, regid], session}, state) do
        %{id: sid} = session

        found = find_procedure(state, regid, [sid: sid])

        state =
            if is_nil(found) do

                payload = [
                    @error, @unregister, %{}, 
                    "wamp.error.no_such_registration"
                ]

                send(state.router, {:push, sid, payload})
                state

            else

                payload = [@unregistered, request]

                send(state.router, {:push, sid, payload})

                {uri, index} = found

                procs = state |> Map.get(:procedures) |> Map.get(uri)

                proc = Enum.at(procs, index)
                    
                Task.start(state.dealer, :unregistered, [proc])

                procedures = Wamp.Enum.remove_item_at(procs, index)

                update_procedures(state, uri, procedures)

            end

        {:noreply, state}
    end

    @impl true
    def handle_info({[@error, @invocation, request, details, uri, args, kwargs], session}, state) do

        %{id: callee_sid} = session

        index = 
            Map.get(state, :invocations)
            |> Enum.find_index(fn 
                %{request: ^request, callee_sid: ^callee_sid} -> true
                _ -> false
            end)

        state = 
            if is_nil(index) do
                state
            else

                inv = Map.get(state, :invocations) |> Enum.at(index)
                                        
                ignore = [:canceled_skip, :canceled_kill]

                if inv not in ignore do
                    reply = [@error, @call, inv.call.request, details, uri, args, kwargs]
                    send(state.router, {:push, inv.caller_sid, reply})
                end

                Map.update!(state, :invocations, fn invs ->
                    head = Enum.slice(invs, 0, index)
                    tail = Enum.slice(invs, index + 1, length(invs))
                    head ++ tail
                end)
            end
        {:noreply, state}
    end

    @impl true
    def handle_info({[@call, request, opts, uri, args, kwargs], session}, state) do
        %{id: sid} = session

        procs = 
            state
            |> Map.get(:procedures)
            |> Map.get(uri, [])
            |> Enum.filter(fn 
                %{status: :registered} -> 
                    true
                _ -> 
                    false
            end)
        
        state =
            if length(procs) == 0 do
                code = "wamp.error.procedure_not_found"
                payload = [@error, @call, request, %{}, code]
                send(state.router, {:push, sid, payload})
                state
            else
                
                call = %{
                    args: args,
                    options: opts,
                    request: request,
                    kwargs: kwargs,
                }

                choice = 
                    case apply(state.dealer, :select, [{uri, call}, procs, session]) do
                        {:ok, proc} ->
                            {:ok, proc, opts}

                        {:ok, proc, details} ->
                            {:ok, proc, details}

                        other ->
                            other
                    end



                case choice do

                    {:ok, %{id: regid, sid: callee_sid}, details} ->

                        details = 
                            case opts do
                                %{"disclose_me" => true} ->
                                    Map.put(details, :caller, sid)
                                _ -> 
                                    details
                            end

                        details =
                            case opts do
                                %{"progress" => true} ->
                                    Map.put(details, :progress, true)

                                _ -> details
                            end


                        {:ok, reqid, state } = 
                            if callee_sid === :dealer do
                                {id, state} = gen_next_id(state)
                                {:ok, id, state}
                            else
                                {:ok, id} = 
                                    GenServer.call(state.router, {:nextid, callee_sid})
                                {:ok, id, state}
                            end

                        inv = %{
                            call: call,
                            status: :pending,
                            request: reqid, 
                            caller_sid: sid, 
                            callee_sid: callee_sid, 
                            invoked_at: DateTime.utc_now,
                        }

                        reply = [@invocation, reqid, regid, details, args, kwargs]
                        send(state.router, {:push, callee_sid, reply})

                        Map.update!(state, :invocations, &(&1 ++ [inv]))

                    {:error, reason} ->
                        payload = [@error, @call, request, %{}, reason]
                        send(state.router, {:push, sid, payload})
                        state

                    _ ->
                        code = "wamp.dealer.call_error"
                        payload = [@error, @call, request, %{}, code]
                        send(state.router, {:push, sid, payload})
                        state
                end

            end
        {:noreply, state}
    end

    @impl true
    def handle_info({[@yield, request, options, args, kwargs], session}, state) do
        %{id: callee_sid} = session

        index = 
            state
            |> Map.get(:invocations)
            |> Enum.find_index(fn 
                %{request: ^request, callee_sid: ^callee_sid} -> true
                _ -> false
            end)

        state =
            if is_nil(index) do

                state

            else

                inv = Map.get(state, :invocations) |> Enum.at(index)
                                        
                state = 
                    case {options, inv.call.options} do

                        { %{"progress" => true}, %{"progress" => true} } ->
                            state

                        _ ->
                            Map.update!(state, :invocations, fn invs ->
                                head = Enum.slice(invs, 0, index) 
                                tail = Enum.slice(invs, index + 1, length(invs))
                                head ++ tail
                            end)
                    end

                if not is_nil(inv.caller_sid) and inv.status === :pending do
                    payload = [@result, inv.call.request, %{}, args, kwargs]
                    send(state.router, {:push, inv.caller_sid, payload}) 
                end

                state
            end
        {:noreply, state}
    end

    @impl true
    def handle_info({:disconnected, session}, state) do
        %{id: sid} = session

        filter = fn 
            %{sid: ^sid} ->
                false
            _ ->
                true
        end

        state =
            state
            |> Map.update!(:procedures, fn procedures -> 
                procedures
                |> Map.keys()
                |> Enum.reduce(procedures, fn uri, procedures -> 
                    Map.update!(procedures, uri, fn procs -> 
                        Enum.filter(procs, filter)
                    end)
                end)
            end)
            |> Map.update!(:invocations, fn invs -> 
                Enum.filter(invs, fn 
                    %{callee_sid: ^sid, call: %{request: req}, caller_sid: caller_sid} ->

                        if not is_nil(caller_sid) do
                            code = "wamp.error.callee_shutdown"
                            payload = [@error, @call, req, %{}, code]
                            send(state.router, {:push, caller_sid, payload})  
                        end

                        false
                    _ ->
                        true
                end)
                |> Enum.map(fn 
                    %{caller_sid: ^sid} = invocation ->
                        Map.put(invocation, :caller_sid, nil)
                    any ->
                        any
                end)

            end)

        {:noreply, state}
    end

    @impl true
    def handle_call({:revoke, regid, reason}, _from, state) do

        found = find_procedure(state, regid)

        {reply, state} =
            if not is_nil(found) do

                {uri, index} = found

                procs = Map.get(state.procedures, uri)

                proc = Enum.at(procs, index)

                details = %{
                    "registration" => proc.id,
                    "reason" => reason
                }

                payload = [@unregistered, 0, details]

                send(state.router, {:push, proc.sid, payload}) 

                Task.start(state.dealer, :unregistered, [proc])

                procedures = Wamp.Enum.remove_item_at(procs, index)

                state = update_procedures(state, uri, procedures)

                {:ok, state}

            else
                {:notfound, state}
            end

        {:reply, reply, state}
    end

    @impl true
    def handle_call({:approve, sid, uri, attr}, _from, state) do

        procs = 
            state
            |> Map.get(:procedures)
            |> Map.get(uri, [])

        index = 
            procs
            |> Enum.find_index(fn 
                %{sid: ^sid, status: :pending} -> 
                    true
                _ -> 
                    false
            end)

        if index do

            { id, state } = gen_next_id(state)

            proc =
                procs
                |> Enum.at(index)
                |> Map.merge(%{id: id, status: :registered, attributes: attr})

            payload = [@registered, proc.request, id]

            send(state.router, {:push, sid, payload}) 

            procedures = Wamp.Enum.replace_item_at(procs, index, proc)

            state = update_procedures(state, uri, procedures)

            {:reply, proc, state}

        else
            {:reply, {:error, :not_found}, state}
        end

    end

    @impl true
    def handle_call({:reject, sid, uri, error}, _from, state) do
        procs = 
            state
            |> Map.get(:procedures)
            |> Map.get(uri, [])

        index = 
            procs
            |> Enum.find_index(fn 
                %{sid: ^sid, status: :pending} -> 
                    true
                _ -> 
                    false
            end)

        if index do

            proc = procs |> Enum.at(index)

            procedures = Wamp.Enum.remove_item_at(procs, index)

            state = update_procedures(state, uri, procedures) 

            payload = [@error, @register, proc.request, %{}, error]

            send(state.router, {:push, sid, payload}) 

            {:reply, :ok, state}
        else
            {:reply, :error, state}
        end
    end

    @impl true
    def handle_call({:procedures, uri}, _from, state) do
        procedures = 
            state
            |> Map.get(:procedures)
            |> Map.get(uri, [])

        {:reply, procedures, state}
    end

    @impl true
    def handle_call({:get, prop}, _from, state) when is_atom(prop) do
        {:reply, Map.get(state, prop), state}
    end

    @impl true
    def handle_call({:features, session}, _from, state) do
        {:reply, features(session), state}
    end

    @doc """
    Finds a procedure registration by its ID across all URIs.

    Returns `{uri, index}` if found, or `nil` if not found.
    Accepts optional keyword list of additional property filters.
    """
    def find_procedure(state, regid, opts \\ []) do
        procs = Map.get(state, :procedures)
        find_procedure(procs, regid, Map.keys(procs), opts)
    end

    @doc false
    def find_procedure(procedures, regid, [uri | uris], opts) do
        index = 
            procedures
            |> Map.get(uri, [])
            |> Enum.find_index(fn 
                %{id: ^regid} = proc -> 
                    match_true(proc, opts)
                _ -> 
                    false
            end)

        if is_nil(index) do
            find_procedure(procedures, regid, uris, opts)
        else
            {uri, index}
        end
    end

    @doc false
    def find_procedure(_procs, _regid, [], _opts) do
        nil
    end

    @doc false
    def match_true(_proc, []) do
        true
    end

    @doc false
    def match_true(proc, [{prop, value} | opts]) do
        if Map.get(proc, prop) == value do
            match_true(proc, opts)
        else
            false
        end
    end

    @doc """
    Updates the procedures for a URI. Removes the URI key if the
    procedure list is empty.
    """
    def update_procedures(state, uri, []) do
        state
        |> Map.update!(:procedures, &Map.delete(&1, uri))
    end

    def update_procedures(state, uri, procedures) do
        state
        |> Map.update!(:procedures, &Map.put(&1, uri, procedures))
    end

    defp gen_next_id(state) do
        id = Map.get(state, :next_id)
        {id, Map.update!(state, :next_id, &(&1 + 1))}
    end

    @doc """
    Processes a registration request by delegating to the custom dealer module.

    Called in a separate task to avoid blocking the dealer's message queue.
    On approval, the registration is confirmed and the client is notified.
    On rejection, the client receives an error.
    """
    def register(server, dealer, { uri, opts, session }) do
        case apply(dealer, :register, [{uri, opts}, session]) do

            {:ok, attr} ->
                server
                |> GenServer.call({:approve, session.id, uri, attr})

            {:error, reason} ->
                server
                |> GenServer.call({:reject, session.id, uri, reason})

            _ ->
                nil
        end
    end


end
