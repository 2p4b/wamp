defmodule Wamp.Session do
    @moduledoc """
    Represents a WAMP client session.

    A session is established when a client successfully connects to a router
    and completes the authentication handshake.

    ## Fields

      * `:id` - (required) unique session identifier
      * `:pid` - (required) the PID of the client process
      * `:details` - connection details exchanged during handshake (default: `%{}`)
      * `:request_count` - number of requests made in this session (default: `0`)
    """

    @enforce_keys [:id, :pid]

    defstruct [
        :id,
        :pid,
        details: %{},
        request_count: 0
    ]

end
