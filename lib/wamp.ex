defmodule Wamp do
    @moduledoc """
    Documentation for `Wamp`.
    """

    @doc """
    Hello world.

    ## Examples

        iex> Wamp.hello()
        :world

    """
    use Application

    def start(_type, _args) do

        children = [
        ]

        Supervisor.start_link(children, strategy: :one_for_one, name: Wamp.Supervisor)
    end

    def hello do
        :world
    end

end
