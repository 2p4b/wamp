defmodule Wamp.Session do

    @enforce_keys [:id, :process]

    defstruct [
        :id, 
        :pid,
        details: %{},
        request_count: 0
    ]

end
