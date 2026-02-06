defmodule Wamp.RPC.Procedure do
    defstruct [
        :id, 
        :sid, 
        :uri, 
        :status,
        :options,
        :request,
        :attributes,
    ]
end
