defmodule Wamp.Spec do
    @moduledoc """
    WAMP protocol message type constants.

    This module defines all WAMP message type codes as module attributes.
    Use `use Wamp.Spec` to inject them into your module.

    ## Message Type Codes

    ### Session Lifecycle

    | Attribute       | Code | Description                        |
    |-----------------|------|------------------------------------|
    | `@hello`        | 1    | Client initiates session           |
    | `@welcome`      | 2    | Router confirms session            |
    | `@abort`        | 3    | Router/client aborts session       |
    | `@challenge`    | 4    | Router sends auth challenge        |
    | `@authenticate` | 5    | Client responds to challenge       |
    | `@goodbye`      | 6    | Graceful session close             |
    | `@error`        | 8    | Error response to a request        |

    ### Publish & Subscribe

    | Attribute         | Code | Description                      |
    |-------------------|------|----------------------------------|
    | `@publish`        | 16   | Client publishes an event        |
    | `@published`      | 17   | Broker confirms publication      |
    | `@subscribe`      | 32   | Client subscribes to a topic     |
    | `@subscribed`     | 33   | Broker confirms subscription     |
    | `@unsubscribe`    | 34   | Client unsubscribes              |
    | `@unsubscribed`   | 35   | Broker confirms unsubscription   |
    | `@event`          | 36   | Broker delivers event            |

    ### Remote Procedure Calls

    | Attribute         | Code | Description                      |
    |-------------------|------|----------------------------------|
    | `@call`           | 48   | Caller invokes a procedure       |
    | `@cancel`         | 49   | Caller cancels a call            |
    | `@result`         | 50   | Dealer returns call result       |
    | `@register`       | 64   | Callee registers a procedure     |
    | `@registered`     | 65   | Dealer confirms registration     |
    | `@unregister`     | 66   | Callee unregisters a procedure   |
    | `@unregistered`   | 67   | Dealer confirms unregistration   |
    | `@invocation`     | 68   | Dealer invokes a callee          |
    | `@interrupt`      | 69   | Dealer interrupts an invocation  |
    | `@yield`          | 70   | Callee returns invocation result |

    ## Usage

        defmodule MyModule do
            use Wamp.Spec

            def hello_message(realm, details) do
              [@hello, realm, details]
            end
        end
    """

    defmacro __using__(_opts) do
        quote do
            Module.put_attribute(__MODULE__, :hello, 1)
            Module.put_attribute(__MODULE__, :welcome, 2)
            Module.put_attribute(__MODULE__, :abort, 3)
            Module.put_attribute(__MODULE__, :challenge, 4)
            Module.put_attribute(__MODULE__, :authenticate, 5)
            Module.put_attribute(__MODULE__, :goodbye, 6)
            Module.put_attribute(__MODULE__, :error, 8)

            Module.put_attribute(__MODULE__, :publish, 16)
            Module.put_attribute(__MODULE__, :published, 17)

            Module.put_attribute(__MODULE__, :subscribe, 32)
            Module.put_attribute(__MODULE__, :subscribed, 33)
            Module.put_attribute(__MODULE__, :unsubscribe, 34)
            Module.put_attribute(__MODULE__, :unsubscribed, 35)
            Module.put_attribute(__MODULE__, :event, 36)

            Module.put_attribute(__MODULE__, :call, 48)
            Module.put_attribute(__MODULE__, :result, 50)

            Module.put_attribute(__MODULE__, :register, 64)
            Module.put_attribute(__MODULE__, :registered, 65)
            Module.put_attribute(__MODULE__, :unregister, 66)
            Module.put_attribute(__MODULE__, :unregistered, 67)
            Module.put_attribute(__MODULE__, :invocation, 68)
            Module.put_attribute(__MODULE__, :yield, 70)

            Module.put_attribute(__MODULE__, :cancel, 49)
            Module.put_attribute(__MODULE__, :interrupt, 69)

            Module.put_attribute(__MODULE__, :max_id, 9_007_199_254_740_992)
        end

    end
end
