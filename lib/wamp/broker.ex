defmodule Wamp.Broker do

    @type session :: map

    @callback publish({topic :: String.t(), event :: map}, publisher :: session, subscribers :: [session]) :: {:ok, [session]} | {:error, uri :: String.t()}

    @callback subscribe(topic :: String.t(), opts :: map,  subscriber :: session) :: { :ok, term } | {:error, uri :: String.t()}

    @callback unsubscribed(subsciption :: session) :: any

end
