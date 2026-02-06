defmodule Wamp.Spec.Broker do

    @callback capabilities(Integer.t, Map.t) :: Map.t

    @callback publish(String.t, Map.t) :: {:ok, Integer.t} | :error

    @callback subscribe(String.t, Function.t) :: {:ok, Integer.t} | :error

    @callback unsubscribe(Integer.t) :: :ok | :error

end
