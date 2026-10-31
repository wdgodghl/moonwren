# Security policy and threat model

## Supported security boundary

The root runtime performs no filesystem, environment, process, or network I/O.
Host access is opt-in through loaders, foreign callbacks, or the separate
`host` package. `VmLimits` bounds interpreter steps, call depth, captured output,
module count, runtime objects, and source size; hosts can also request
cancellation at interpreter checkpoints.

These controls turn common resource exhaustion into structured failures. They
do **not** make MoonWren an operating-system security sandbox and do not provide
hard memory, CPU-time, process, or network isolation. Mutually hostile or
untrusted tenants should run in separate restricted processes or containers.

## Host responsibilities

- Treat loaders and foreign callbacks as trusted host code.
- Grant only the minimum `HostAccessPolicy` capabilities needed by a script.
- Keep loader roots application-controlled. Path containment checks do not
  eliminate every symbolic-link race; process isolation is required for hostile
  filesystem access.
- Set finite limits for untrusted input and enforce a host-side wall-clock
  timeout around the process.
- Release retained handles and close persistent VMs when their owner ends.
- Never place credentials in Wren source, diagnostics, replay logs, or shared
  playground URLs.

## Supported versions

Security fixes are applied to the latest Mooncakes release. Older pre-1.0
versions may require upgrading rather than a backport.

## Reporting a vulnerability

Do not include credentials, personal data, or exploit details in a public
issue. Open a minimal GitHub issue asking for a private contact channel, with
only the affected version and a high-level impact summary. General correctness
bugs that do not expose sensitive information may use the public bug template.
