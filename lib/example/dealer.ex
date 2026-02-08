defmodule Wamp.Example.Dealer do
    @moduledoc """
    Example dealer implementation that approves all registrations and selects
    the first matching procedure for invocations.

    This is the default dealer used when no custom dealer is specified in
    `use Wamp.Router`. Override this with your own module to add authorization,
    load balancing, or custom routing logic.

    ## Implementing a Custom Dealer

        defmodule MyApp.Dealer do
          @behaviour Wamp.Dealer

          def register({uri, opts}, session) do
            # Return {:ok, attributes} to approve or {:error, reason} to reject
            {:ok, nil}
          end

          def procedure({uri, call}, caller, procedures) do
            # Select which registered callee should handle the call
            # Implement round-robin, load balancing, etc.
            {:ok, List.first(procedures)}
          end

          def unregistered(procedure) do
            # Cleanup after unregistration
          end
        end
    """

    @behaviour Wamp.Dealer

    @doc "Approves all procedure registration requests."
    def register({_topic, _opts}, _session) do
        {:ok, nil}
    end

    @doc """
        Selects the first registered procedure for invocation and disclose
        the caller to the callee selectively
    """
    def select({_topic, _call}, [%{uri: "wamp." <> _rest} = proc], %{id: id}) do
        {:ok, proc, %{callee: id}}
    end

    def select({_topic, _call}, [proc | _],  _caller_session) do
        { :ok, proc}
    end


    @doc "No-op cleanup after unregistration."
    def unregistered(_) do
    end

end
