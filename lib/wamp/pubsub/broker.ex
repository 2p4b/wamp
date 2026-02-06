defmodule Wamp.PubSub.Broker do

    use GenServer

    use Wamp.Spec

    def features(_session) do
        %{
            "event_retention" => false,
            "session_meta_api" => true,
            "publisher_exclusion" => true,
            "payload_transparency" => true,
            "subscription_meta_api" => true,
            "subscription_revocation" => true,
            "publisher_identification" => true,
            "pattern_based_subscription" => false,
            "payload_encryption_cryptobox" => false,
            "subscriber_blackwhite_listing" => true,
        }
    end

    def start_link(default) do
        name = 
            default
            |> Keyword.get(:realm)
            |> Wamp.Router.broker_name()

        GenServer.start_link(__MODULE__, default, name: name)
    end

    @impl true
    def init(args) do
        {:ok, 
            %{ 
                pid: self(),
                realm: Keyword.get(args, :realm),
                broker: Keyword.get(args, :broker),
                next_id: 0,
                router: Keyword.get(args, :router),
                subscriptions: %{},
                publication_count: 0,
            }
        }
    end

    @impl true
    def handle_info({[@subscribe, request, opts, topic], session}, state) do
        %{id: sid, auth: %{authrole: authrole, authid: authid} } = session 

        sub = 
            state
            |> Map.get(:subscriptions)
            |> Map.get(topic, [])
            |> Enum.find(fn 
                %{sid: ^sid} -> 
                    true

                _ -> 
                    false
            end)

        state =
            if is_nil(sub) do

                sub = %{
                    id: nil, 
                    sid: sid, 
                    topic: topic,
                    options: opts,
                    authid: authid,
                    authrole: authrole,
                    status: :pending,
                    request: request, 
                    attributes: []
                }

                args = {topic, opts, session}

                # Start new process to handle subsciption 
                # so to not hold up the event 
                # processing queue
                Task.start(__MODULE__, :subscribe, [self(), state.broker, args])

                subs = 
                    state
                    |> Map.get(:subscriptions) 
                    |> Map.get(topic, [])

                update_subscriptions(state, topic, subs ++ [sub])

            else
                case sub do
                    %{status: :pending} ->
                        error = "wamp.error.subscription_already_exists"
                        payload = [@error, @subscribe, request, %{}, error]
                        send(state.router, {:push, sid, payload}) 
                        
                    %{status: :subscribed}
                        payload = [@subscribed, request, sub.id]
                        send(state.router, {:push, sid, payload}) 
                end
                state
            end

        {:noreply, state}
    end

    @impl true
    def handle_info({[@unsubscribe, request, subid], session}, state) do
        %{id: sid} = session

        found = find_subscription(state, subid)

        state =
            if not is_nil(found) do

                {topic, index} = found

                subs = 
                    state
                    |> Map.get(:subscriptions)
                    |> Map.get(topic)

                sub =  Enum.at(subs, index)

                payload = [@unsubscribed, request]

                send(state.router, {:push, sid, payload}) 

                Task.start(state.broker, :unsubscribed, [sub])

                head = Enum.slice(subs, 0, index)
                tail = Enum.slice(subs, index + 1, length(subs))

                update_subscriptions(state, topic, head ++ tail)

            else
                payload = [
                    @error, 
                    @unsubscribe, 
                    request, %{}, 
                    "wamp.error.subscription.not_found"
                ]
                send(state.router, {:push, sid, payload}) 
                state
            end
        {:noreply, state}
    end

    @impl true
    def handle_info({[@publish, request, opts, topic, args, kwargs], session}, state) do

        %{id: from} = session

        restrictions = 
            ["exclude", "eligible", 
                "eligible_authid", "eligible_authrole",
                    "exclude_authid", "exclude_authrole"]

        exclude_me = Map.get(opts, "exclude_me", true)


        filters = 
            [{"exclude_me", exclude_me}] ++ collect_filters(opts, restrictions)


        subs = 
            state
            |> Map.get(:subscriptions)
            |> Map.get(topic, [])
            |> Enum.filter(&filter(&1, from, filters))

        event = %{
            args: args,
            options: opts,
            kwargs: kwargs,
            request: request,
        }

        publication = 
            try do
                apply(state.broker, :publish, [{topic, event}, session, subs])
            catch
                _ ->
                    {:error, "wamp.error.publication"}
            end


        state =
            case publication do

                {:ok, subscriptions} ->

                    {pubid , state} = 
                        state 
                        |> increament(:publication_count)

                    if length(subscriptions) > 0 do

                        details = 
                            if Map.get(opts, "disclose_me", false) do
                                %{"publisher" => from } 
                            else
                                %{}
                            end

                        messages =
                            subscriptions
                            |> Enum.map( fn %{id: subid, sid: sid} -> 
                                {sid, [@event, subid, pubid, details, args, kwargs]}
                            end)

                        send(state.router, {:push, messages}) 
                    end

                    if Map.get(opts, "acknowledge", false) === true do
                        payload = [@published, request, pubid]
                        send(state.router, {:push, from, payload}) 
                    end

                    state

                {:error, uri} ->
                    if Map.get(opts, "acknowledge", false) === true do
                        payload = [@error, @publish, request, {}, uri]
                        send(state.router, {:push, from, payload}) 
                    end
                    state

            end

        {:noreply, state}
    end

    @impl true
    def handle_info({:disconnected, %{id: sid}}, state) do

        %{broker: broker} = state

        state = 
            state
            |> Map.update!(:subscriptions, fn topics -> 
                topics
                |> Map.keys()
                |> Enum.reduce(topics, fn topic, topics -> 
                    Map.update!(topics, topic, fn subscriptions -> 
                        Enum.filter(subscriptions, fn
                            %{sid: ^sid} = sub -> 
                                Task.start(broker, :unsubscribed, [sub])
                                false

                            _ -> 
                                true
                        end)
                    end)
                end)
            end)


        {:noreply, state}
    end

    @impl true
    def handle_call({:approve, sid, topic, attr}, _from, state) do

        subs = 
            state
            |> Map.get(:subscriptions)
            |> Map.get(topic, [])

        index = 
            subs
            |> Enum.find_index(fn 
                %{sid: ^sid, status: :pending} -> 
                    true
                _ -> 
                    false
            end)

        if index do
            {id, state} = state |> increament(:next_id)

            sub =
                subs
                |> Enum.at(index)
                |> Map.merge(%{id: id, status: :subscribed, assigns: attr})

            head = Enum.slice(subs, 0, index)
            tail = Enum.slice(subs, index + 1, length(subs))
            subscriptions = head ++ [sub] ++ tail


            payload = [@subscribed, sub.request, id]
            send(state.router, {:push, sid, payload}) 

            state = update_subscriptions(state, topic, subscriptions)

            {:reply, sub, state}

        else
            {:reply, {:error, :subscription_not_found}, state}
        end

    end

    @impl true
    def handle_call({:reject, sid, topic, error}, _from, state) do
        subs = 
            state
            |> Map.get(:subscriptions)
            |> Map.get(topic, [])

        index = 
            subs
            |> Enum.find_index(fn 
                %{sid: ^sid, status: :pending} -> 
                    true
                _ -> 
                    false
            end)

        if index do

            sub = subs |> Enum.at(index)

            head = Enum.slice(subs, 0, index)
            tail = Enum.slice(subs, index + 1, length(subs))
            subscriptions = head ++ tail

            state = update_subscriptions(state, topic, subscriptions) 

            payload = [@error, @subscribe, sub.request, %{}, error]
            send(state.router, {:push, sid, payload}) 
            {:reply, :ok, state}
        else
            {:reply, :error, state}
        end
    end

    @impl true
    def handle_call({:features, session}, _from, state) do
        {:reply, features(session), state}
    end

    @impl true
    def handle_call({:subscriptions, topic}, _from, state) do
        subscriptions = 
            state
            |> Map.get(:subscriptions)
            |> Map.get(topic, [])

        {:reply, subscriptions, state}
    end

    @impl true
    def handle_call({:get, prop}, _from, state) when is_atom(prop) do
        {:reply, Map.get(state, prop), state}
    end

    @impl true
    def handle_call({:revoke, subid, reason}, _from, state) do
        found = 
            state
            |> find_subscription(subid)

        if not is_nil(found) do
            {topic, index} = found

            subs = Map.get(state.subscriptions, topic)

            sub = Enum.at(subs, index)

            details = %{
                "subscription" => sub.id,
                "reason" => reason
            }

            payload = [@unsubscribed, 0, details]

            send(state.router, {:push, sub.sid, payload}) 

            Task.start(state.broker, :unsubscribed, [sub])

            subscriptions = Wamp.Enum.remove_item_at(subs, index)

            state = update_subscriptions(state, topic, subscriptions) 

            {:reply, :ok, state}

        else
            {:reply, :not_found, state}
        end
    end

    def find_subscription(state, subid, opts \\ []) 
    when is_integer(subid) do
        subscriptions = Map.get(state, :subscriptions)
        find_subscription(subscriptions, subid, Map.keys(subscriptions), opts)
    end

    def find_subscription(subscriptions, subid, [topic | topics], opts) 
    when is_integer(subid) do
        index = 
            subscriptions
            |> Map.get(topic, [])
            |> Enum.find_index(fn 
                %{id: ^subid} = sub -> 
                    match_true(sub, opts)
                _ -> 
                    false
            end)

        if is_nil(index) do
            find_subscription(subscriptions, subid, topics, opts)
        else
            {topic, index}
        end
    end

    def find_subscription(_subs, _subid, [], _opts) do
        nil
    end

    def match_true(_sub, []) do
        true
    end

    def match_true(sub, [{prop, value} | opts]) do
        if Map.get(sub, prop) == value do
            match_true(sub, opts)
        else
            false
        end
    end

    def update_subscriptions(state, topic, []) do
        state
        |> Map.update!(:subscriptions, &Map.delete(&1, topic))
    end

    def update_subscriptions(state, topic, subscriptions) do
        state
        |> Map.update!(:subscriptions, &Map.put(&1, topic, subscriptions))
    end

    def subscribe(server, broker, {topic, options, session}) do
        case apply(broker, :subscribe, [topic, options, session]) do

            {:ok, attr} ->
                server
                |> GenServer.call({:approve, session.id, topic, attr})

            {:error, reason} ->
                server
                |> GenServer.call({:reject, session.id, topic, reason})

            _ ->
                nil
        end
    end

    defp increament(state, prop) when is_atom(prop) do
        state = Map.update!(state, prop, &(&1 + 1))
        { Map.get(state, prop), state }
    end

    defp collect_filters(opts, [filter | filters]) do
        if Map.has_key?(opts, filter) do
            [{filter, Map.get(opts, filter)}] ++ collect_filters(opts, filters)
        else
            collect_filters(opts, filters)
        end
    end

    defp collect_filters(_opts, []) do
        []
    end

    defp filter(%{sid: sid}=sub, from, [{"exclude_me", exclude_me} | filters])
    when (sid !== from) or (exclude_me === false) do
        filter(sub, from, filters)
    end

    defp filter(%{sid: sid}=sub, from, [{"eligible", eligible} | filters])
    when is_list(eligible) do
        if sid in eligible do
            filter(sub, from, filters)
        else
            false
        end
    end

    defp filter(%{sid: sid}=sub, from, [{"exclude", exclude} | filters])
    when is_list(exclude) do
        if sid in exclude do
            false
        else
            filter(sub, from, filters)
        end
    end

    defp filter(%{authid: id}=sub, from, [{"eligible_authid", ids} | filters])
    when is_list(ids) do
        if id in ids do
            filter(sub, from, filters)
        else
            false
        end
    end

    defp filter(%{authrole: role}=sub, from, [{"eligible_authrole", roles} | filters])
    when is_list(roles) do
        if role in roles do
            filter(sub, from, filters)
        else
            false
        end
    end

    defp filter(%{authid: id}=sub, from, [{"exclude_authid", ids} | filters])
    when is_list(ids) do
        if id in ids do
            false
        else
            filter(sub, from, filters)
        end
    end

    defp filter(%{authrole: role}=sub, from, [{"exclude_authrole", roles} | filters])
    when is_list(roles) do
        if role in roles do
            false
        else
            filter(sub, from, filters)
        end
    end

    defp filter(_, _, []) do
        true
    end

    defp filter(_sub, _from, _filters) do
        false
    end

end
