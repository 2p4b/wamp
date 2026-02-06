defmodule WampTest do
    use ExUnit.Case
    doctest Wamp

    test "greets the world" do
        assert Wamp.hello() == :world
    end
end
