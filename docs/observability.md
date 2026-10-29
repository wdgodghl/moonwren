# Runtime observability

Wrap a persistent VM with `ObservedVm` to collect one `VmTelemetry` snapshot
after each interpreted module, global read, retained call, or batch reload.
Snapshots include:

- operation id, kind, source, success, and diagnostic count;
- evaluator steps, wall-clock duration, output lines and characters;
- loaded modules, live runtime objects and Fibers;
- foreign binding calls and peak Wren call depth;
- objects reclaimed by the most recently recorded GC pass.

Observers receive snapshots synchronously after the VM operation finishes and
must not re-enter that VM. The in-memory history has a caller-selected bound,
so enabling telemetry does not create an unbounded production queue. The
underlying VM remains available for advanced APIs such as schedulers, handles,
state snapshots, and explicit collection.

`telemetry_prometheus` exports aggregate operation success/failure, steps,
foreign calls, and duration in Prometheus text exposition format.
`telemetry_chrome_trace` exports complete-duration events with source, result,
step, and object arguments for Chrome Trace and Perfetto. Neither exporter
includes source code, variable values, host arguments, personal information,
or environment contents.
