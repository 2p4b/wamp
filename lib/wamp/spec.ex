defmodule Wamp.Spec do
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
