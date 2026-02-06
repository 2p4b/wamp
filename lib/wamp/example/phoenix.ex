defmodule Wamp.Example.Phoenix do

    use Wamp.Transport.Phoenix,
        router: Wamp.Example.Router

    def connection(socket) do
        {:ok, socket}
    end

end
