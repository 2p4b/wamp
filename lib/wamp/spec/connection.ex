defmodule Wamp.Spec.Connection do
    @moduledoc """
    Represents the transport-level connection metadata for a WAMP session.

    This struct is typically created by the transport layer (e.g. `Wamp.Transport.Phoenix`)
    and passed along with the HELLO message to the router.

    ## Fields

      * `:id` - transport-level connection identifier (default: `nil`)
      * `:assigns` - arbitrary metadata map for storing custom connection data (default: `%{}`)
      * `:serializer` - the serialization format used (e.g. `:json`, `:msgpack`) (default: `nil`)
    """

    defstruct   id: nil,
                assigns: %{},
                serializer: nil

end
