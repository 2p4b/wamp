defmodule Wamp.Example.Client do

    use Wamp.Client,
        otp_app: :web


    procedure "math.sum", Wamp.Enum, :sum

    procedure "math.multiply", Wamp.Enum, :multiply

    procedure "math.ackermann", Wamp.Enum, :ackermann

    channel "client.session", Wamp.Example.Subscriber

end
