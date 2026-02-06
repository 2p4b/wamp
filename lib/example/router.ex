defmodule Wamp.Example.Router do
    @moduledoc """
    Example WAMP router using the default broker and dealer.

        Wamp.Example.Router.start_link(realm: "realm1")
    """
    use Wamp.Router,
        otp_app: :wamp
end
