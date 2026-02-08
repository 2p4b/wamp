defmodule Wamp.Dealer do
    @type session :: map

    @type procedure :: map

    @callback register({topic :: String.t(),  opts :: map},  session :: session) :: {:ok, any } | {:error, uri :: String.t()}

    @callback select({uri :: String.t(), call :: map}, procedures :: [ procedure ], caller :: session) :: { :ok,  procedure } | {:error, uri :: String.t()}

    @callback unregistered(procedure :: procedure) :: any

end
