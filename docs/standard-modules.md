# Portable standard modules

MoonWren includes portable modules that are loaded by the runtime without
granting ambient process access:

- `moon/json`: strict nested JSON parsing plus List/Map serialization, finite
  number validation, String-key enforcement, escaping, and cycle detection;
- `moon/base64`: RFC 4648 UTF-8 text encoding and byte-preserving decoding;
- `moon/url`: UTF-8 URL component percent encoding and strict decoding;
- `moon/uuid`: deterministic SHA-256 name identifiers encoded as UUID version
  8. This is deliberately not labelled UUID v5, whose algorithm is SHA-1;
- `moon/http`: scheduler-mediated request descriptors.

`Http.get(url)` and `Http.request(...)` suspend the calling Fiber with a Map
containing `$moonwren: "http"`, method, URL, headers, and body. They never open
a socket. The host receives `VmSchedulerExternalRequest`, calls
`snapshot_request` to obtain recursive host-owned data, applies its own domain,
method, header, size, timeout, and TLS policy, and then calls `deliver` with a
response value. This design keeps browser fetch, native clients, test fakes,
and server-side policy outside the language core while preserving one script
API.

Filesystem and environment access remain in the opt-in `host` package. They
are deny-by-default and use an explicit root, read/write flags, byte limits,
and environment allowlist.
