# Multi-tenant VM pool

`VmPool` bounds concurrently active VMs and validates every operation through
an opaque tenant lease. `VmPoolConfig::isolated` is the recommended setting for
untrusted workloads: a released or invalidated VM is closed and replaced before
the slot can serve another script. It prevents modules, globals, handles,
Fibers, foreign objects, and debugger state from crossing requests.

```moonbit
let pool = VmPool::new(VmPoolConfig::isolated(8, 2), fn() {
  Vm::new(limits, loader, methods, classes)
})
match pool.acquire(tenant_id) {
  VmPoolAcquired(lease) => {
    let result = pool.with_vm(lease, fn(vm) { vm.interpret("main", source) })
    ignore(pool.release(lease))
  }
  VmPoolExhausted(reason) => reject_request(reason)
}
```

The pool enforces capacity and per-tenant active-lease limits. Tokens prevent a
released, duplicated, or foreign-pool lease from being reused. `invalidate`
unconditionally replaces the VM after a runtime or host failure. Statistics
report capacity, active leases, creations, recycling, acquisitions, and
rejections.

Trusted session-style workloads may use `VmPoolConfig::new` with
`reset_on_release=false`. A VM is still replaced at `max_uses_per_vm`, and a
slot is replaced before its tenant id changes. State affinity is not promised;
applications needing durable sessions should retain one lease or persist state
explicitly.
