# Changelog

## v0.2.0

### Breaking Changes

- **Dealer callback renamed**: `procedure/3` is now `select/3` with reordered
  arguments `(call_info, procedures, caller_session)`. Custom dealer modules
  must update their implementations.
- **Procedure handler return types**: Handlers must now return tagged tuples
  (`{:ok, args}`, `{:ok, args, kwargs}`, `{:error, uri}`, etc.) instead of
  bare values.

### Added

- `select/3` can return `{:ok, proc, details}` to pass custom invocation
  details to the callee (e.g. selective caller disclosure).
- `Wamp.Example.Dealer` includes a specific `select/3` clause for
  `wamp.`-prefixed URIs that discloses the caller to the callee.
- Router path-based `get/1` accepts a list of keys for nested state traversal,
  resolving maps by key and lists by `:id` match.
- Router `session/2` convenience function for looking up sessions by id.
- Procedure handlers can return `{:error, uri, ...}` tuples directly as an
  alternative to raising `Wamp.Client.InvocationError`.

### Fixed

- Router `get/1` guard accepts both atom and list arguments.
