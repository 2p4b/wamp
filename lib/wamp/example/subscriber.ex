defmodule Wamp.Example.Subscriber do

    use Wamp.Subscriber

    def handle_event({_pubid, _details, args, _kwargs}, sub) do
        {:noreply, sub}
    end

end
