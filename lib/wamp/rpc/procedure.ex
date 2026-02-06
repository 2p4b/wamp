defmodule Wamp.RPC.Procedure do
    @moduledoc """
    Represents a registered WAMP procedure (callee endpoint).

    ## Fields

      * `:id` - unique registration ID assigned by the dealer
      * `:sid` - session ID of the callee that registered the procedure
      * `:uri` - the procedure URI (e.g. `"com.example.add"`)
      * `:status` - registration status (`:pending`, `:registered`, `:error`, `:canceling`)
      * `:options` - registration options provided by the callee
      * `:request` - the original request ID
      * `:attributes` - custom attributes set by the dealer module on approval
    """

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
