# Deterministic scheduler record and replay

`VmSchedulerRecorder` wraps the cooperative scheduler and records the host
actions that can change an asynchronous run: virtual-time advances, structured
responses, cancellations, and every externally observable poll result. The
workload digest should bind the signed module bundle, runtime ABI, capabilities,
and initial task setup.

Call `encode_scheduler_replay_log` to persist the deterministic `MWR1` format.
It supports null, Boolean, finite number, String, raw bytes, Range, List, and
Map responses; live VM objects are rejected. Length-prefixing preserves Unicode,
newlines, NULs, and arbitrary decoded byte strings.

To reproduce a run, create a fresh VM and scheduler, load the same workload,
spawn tasks in the same order, decode the log, and call
`replay_scheduler_log`. A workload-digest mismatch is rejected before any
action. During replay, every recorded observation is compared with the new
request/result/failure and output fingerprint. The first difference reports its
event index plus expected and actual fingerprints, which makes production
asynchronous failures suitable for deterministic regression tests.

`VmScheduler::deliver_owned` materializes host-owned recursive data in the
receiving VM without accepting runtime-local object identifiers. It is also the
recommended boundary for HTTP and other structured host integrations.
