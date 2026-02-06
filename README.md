# Wamp

An Elixir implementation of the [WAMP (Web Application Messaging Protocol)](https://wamp-proto.org/) providing both **Publish & Subscribe** and **Remote Procedure Call** messaging patterns over a single connection.

## Features

- **Publish & Subscribe** - Loosely coupled, many-to-many event distribution
- **Remote Procedure Calls** - Routed, point-to-point procedure invocation
- **Phoenix Integration** - WebSocket transport adapter for Phoenix
- **Extensible Architecture** - Custom broker and dealer modules via behaviours
- **Authentication** - Pluggable challenge-response authentication (anonymous, ticket, WAMP-CRA, SCRAM)
- **Subscriber Filtering** - Black/white listing by session ID, auth ID, or auth role
- **Call Cancellation** - Cancel in-flight RPC calls with skip, kill, or killnowait modes
- **Shared Registration** - Multiple callees can register the same procedure URI

## Installation

Add `wamp` to your list of dependencies in `mix.exs`:

```elixir
def deps do
    [
        {:wamp, "~> 0.1.0"}
    ]
end
```

## Quick Start

### 1. Define a Router

The router is the central component that manages client sessions and coordinates message routing.

```elixir
defmodule MyApp.Router do
    use Wamp.Router,
        otp_app: :my_app
end
```

### 2. Define a Client

Clients connect to a router and can act as callers, callees, publishers, and subscribers.

```elixir
defmodule MyApp.Client do
    use Wamp.Client,
        otp_app: :my_app

    # Auto-register procedures on connect
    procedure "com.myapp.add", MyApp.Math, :add
    procedure "com.myapp.multiply", MyApp.Math, :multiply

    # Auto-subscribe to topics on connect
    channel "com.myapp.events", MyApp.EventHandler
end
```

### 3. Implement Procedure Handlers

Procedure handler functions receive `(args, kwargs, details)`:

```elixir
defmodule MyApp.Math do
    def add(args, _kwargs, _details) do
        Enum.sum(args)
    end

    def multiply([a, b], _kwargs, _details) do
        a * b
    end
end
```

### 4. Implement Event Subscribers

```elixir
defmodule MyApp.EventHandler do
    use Wamp.Subscriber

    def handle_event({_pubid, _details, args, kwargs}, sub) do
        IO.inspect(args, label: "Event received")
        {:noreply, sub}
    end
end
```

### 5. Configure and Start

```elixir
# config/config.exs
config :my_app, MyApp.Router,
    realm: "realm1"

config :my_app, MyApp.Client,
    realm: "realm1",
    router: MyApp.Router
```

Add to your supervision tree:

```elixir
children = [
    {MyApp.Router, realm: "realm1"},
    {MyApp.Client, realm: "realm1", router: MyApp.Router}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Architecture

```
                                +------------------+
                                |   Wamp.Router    |
                                |   (GenServer)    |
                                +--------+---------+
                                         |
                 +-----------------------+-------------------+
                 |                                           |
        +--------v---------+                        +--------v---------+
        | Wamp.PubSub      |                        |  Wamp.RPC        |
        |   .Broker        |                        |   .Dealer        |
        | (GenServer)      |                        | (GenServer)      |
        +---------+--------+                        +--------+---------+
                  |                                          |
          +-------+-------+                           +------+------+
          |               |                           |             |
     Subscribers    Publishers                      Callees     Callers
     (Wamp.Client)                                 (Wamp.Client)
```

The library is organized around these core modules:

| Module | Description |
|--------|-------------|
| `Wamp.Router` | Central message router managing sessions and coordination |
| `Wamp.PubSub.Broker` | Handles topic subscriptions and event distribution |
| `Wamp.RPC.Dealer` | Handles procedure registration and call routing |
| `Wamp.Client` | Client-side protocol (caller, callee, publisher, subscriber) |
| `Wamp.Subscriber` | GenServer wrapper for event subscription handlers |
| `Wamp.Transport.Phoenix` | Phoenix WebSocket transport adapter |
| `Wamp.Spec` | WAMP message type constants |

## Usage

### Remote Procedure Calls

```elixir
# Register a procedure at runtime
MyApp.Client.register("com.myapp.echo", {MyApp.Handlers, :echo})

# Call a procedure
request_id = MyApp.Client.call("com.myapp.add", [1, 2])

# Wait for the result
{:ok, {[3], %{}}} = MyApp.Client.await(request_id)

# Or check if result is ready
case MyApp.Client.yielded(request_id) do
    true  -> MyApp.Client.yield(request_id)
    false -> # still pending
end

# Unregister
MyApp.Client.unregister("com.myapp.echo")
```

### Publish & Subscribe

```elixir
# Subscribe to a topic
MyApp.Client.subscribe("com.myapp.events")

# Publish an event (fire-and-forget)
MyApp.Client.publish("com.myapp.events", ["hello"])

# Publish with keyword arguments
MyApp.Client.publish("com.myapp.events", [], %{"message" => "hello"})

# Publish with acknowledgment
{:ok, publication_id} = MyApp.Client.ack_publish("com.myapp.events", ["hello"])

# Unsubscribe
MyApp.Client.unsubscribe("com.myapp.events")
```

### Publishing Options

```elixir
# Exclude yourself from receiving the event
MyApp.Client.publish("topic", args, %{}, %{"exclude_me" => true})

# Disclose publisher identity to subscribers
MyApp.Client.publish("topic", args, %{}, %{"disclose_me" => true})

# Target specific sessions
MyApp.Client.publish("topic", args, %{}, %{"eligible" => [session_id1, session_id2]})

# Exclude specific sessions
MyApp.Client.publish("topic", args, %{}, %{"exclude" => [session_id3]})

# Filter by auth role
MyApp.Client.publish("topic", args, %{}, %{"eligible_authrole" => ["admin"]})
```

### Error Handling in Procedures

Raise `Wamp.Client.InvocationError` to return a structured error to the caller:

```elixir
def divide([a, b], _kwargs, _details) do
    if b == 0 do
        raise Wamp.Client.InvocationError,
            uri: "com.myapp.error.division_by_zero",
            args: ["Cannot divide by zero"],
            kwargs: %{}
    end
    a / b
end
```

## Phoenix WebSocket Integration

### 1. Define a Transport Module

```elixir
defmodule MyAppWeb.WampTransport do
    use Wamp.Transport.Phoenix,
        router: MyApp.Router

    def connection(socket) do
        # Perform connection-level authorization here
        {:ok, socket}
    end
end
```

### 2. Configure Your Endpoint

```elixir
# lib/my_app_web/endpoint.ex
socket "/ws", MyAppWeb.WampTransport,
    websocket: [
        subprotocols: ["wamp.2.json", "wamp.2.msgpack"]
    ]
```

The transport supports both JSON and MessagePack serialization, negotiated via WebSocket subprotocol.

## Custom Broker and Dealer

### Custom Broker

Implement `Wamp.Spec.Broker` to control subscription approval and event filtering:

```elixir
defmodule MyApp.Broker do
    @behaviour Wamp.Broker

    def publish({topic, event}, publisher, subscribers) do
        # Filter subscribers or reject publication
        authorized = Enum.filter(subscribers, &authorized?(&1, topic))
        {:ok, authorized}
    end

    def subscribe(topic, opts, session) do
        if can_subscribe?(session, topic) do
            {:ok, []}  # attributes
        else
            {:error, "wamp.error.not_authorized"}
        end
    end

    def unsubscribed(_subscription) do
        :ok
    end
end
```

### Custom Dealer

Implement `Wamp.Spec.Dealer` to control registration approval and procedure selection:

```elixir
defmodule MyApp.Dealer do
    @behaviour Wamp.Dealer

    def register({uri, opts}, session) do
        if can_register?(session, uri) do
            {:ok, nil}  # attributes
        else
            {:error, "wamp.error.not_authorized"}
        end
    end

    def procedure({uri, call}, caller, procedures) do
        # Implement load balancing, routing, etc.
        {:ok, Enum.random(procedures)}
    end

    def unregistered(_procedure) do
        :ok
    end
end
```

Use your custom modules:

```elixir
defmodule MyApp.Router do
    use Wamp.Router,
        otp_app: :my_app,
        broker: MyApp.Broker,
        dealer: MyApp.Dealer
end
```

## Authentication

Override `challenge/1` and `check_challenge/3` in your router:

```elixir
defmodule MyApp.Router do
    use Wamp.Router, otp_app: :my_app

    # Return the auth method and challenge data
    def challenge(%{id: sid}) do
        {:ticket, %{}}
    end

    # Verify the client's response
    def check_challenge({:ticket, _challenge}, {token, _details}, session) do
        case verify_token(token) do
            {:ok, user} ->
                {:ok, %{
                  authid: user.id,
                  authrole: user.role,
                  authmethod: :ticket,
                  authprovider: :my_app
                }}

            :error ->
                {:error, "wamp.error.not_authorized"}
        end
    end
end
```

Supported authentication methods:

| Method | Tuple | Description |
|--------|-------|-------------|
| Anonymous | `{:anonymous, details}` | No authentication (default) |
| Ticket | `{:ticket, details}` | Token-based authentication |
| WAMP-CRA | `{:wampcra, details}` | Challenge-Response Authentication |
| SCRAM | `{:scram, details}` | Salted Challenge Response |

## Router Introspection

```elixir
# Get all subscriptions
MyApp.Router.subscriptions()

# Get subscriptions for a topic
MyApp.Router.subscriptions("com.myapp.events")

# Get all registered procedures
MyApp.Router.procedures()

# Get procedures for a URI
MyApp.Router.procedures("com.myapp.add")

# Get active invocations
MyApp.Router.invocations()

# Revoke a subscription (server-initiated)
MyApp.Router.revoke_subscription(subscription_id, "administrative action")

# Revoke a registration (server-initiated)
MyApp.Router.revoke_registration(registration_id, "administrative action")
```

## WAMP Protocol Support

### Implemented

- Session lifecycle (HELLO, WELCOME, ABORT, GOODBYE)
- Challenge-response authentication
- Publish & Subscribe with filtering
- Remote Procedure Calls with cancellation
- Publisher exclusion and identification
- Subscriber allow/deny listing
- Shared procedure registration
- Registration and subscription revocation
- Progressive call results (infrastructure)
- Publication acknowledgment

### Not Yet Implemented

- Pattern-based subscriptions
- Pattern-based registrations
- Payload encryption
- Event retention

## License

MIT License. See [LICENSE](LICENSE) for details.
