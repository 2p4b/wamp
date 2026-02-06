defmodule Wamp.Spec.Dealer do

    @callback capabilities(Integer.t, Map.t) :: Map.t

    @callback yield(Integer.t, Map.t) :: :ok | :error

    @callback cancel(Integer.t, String.t) :: :ok | :error

    @callback invoke(String.t, List.t) :: {:ok, Integer.t} | :error

end
