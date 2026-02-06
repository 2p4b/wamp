defmodule Wamp.Dealer do
    @type session :: map

    @type procedure :: map

    @callback register({topic :: String.t(),  opts :: map},  session :: session) :: {:ok, any } | {:error, uri :: String.t()}

    @callback procedure({uri :: String.t(), call :: map},  caller :: session, procedures :: [ procedure ]) :: { :ok,  procedure } | {:error, uri :: String.t()}

    @callback unregistered(procedure :: procedure) :: any

end
