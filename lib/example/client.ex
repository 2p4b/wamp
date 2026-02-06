defmodule Wamp.Example.Client do
    @moduledoc """
    Example WAMP client that registers math procedures and subscribes
    to a session events channel.

    Demonstrates the `procedure` and `channel` macros for auto-registration
    on connect.
    """

    use Wamp.Client,
        otp_app: :web


    procedure "math.sum", Wamp.Enum, :sum

    procedure "math.multiply", Wamp.Enum, :multiply

    procedure "math.ackermann", Wamp.Enum, :ackermann

    channel "client.session", Wamp.Example.Subscriber

end
