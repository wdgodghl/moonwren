///|
fn pooled_test_vm() -> @moonwren.Vm {
  @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing \{name}") },
    [],
    [],
  )
}

///|
fn acquired_lease(
  pool : @moonwren.VmPool,
  tenant : String,
) -> @moonwren.VmPoolLease raise {
  match pool.acquire(tenant) {
    @moonwren.VmPoolAcquired(value) => value
    @moonwren.VmPoolExhausted(message) => fail(message)
  }
}

///|
test "isolated VM pool prevents state crossing tenant releases" {
  let pool = @moonwren.VmPool::new(
    @moonwren.VmPoolConfig::isolated(1, 1),
    pooled_test_vm,
  )
  let first = acquired_lease(pool, "tenant-a")
  match
    pool.with_vm(first, fn(vm) {
      vm.interpret("main", "var secret = \"tenant-a\"\n")
    }) {
    @moonwren.VmPoolUsed(@moonwren.ProgramCompleted(_, _)) => ()
    _ => fail("first tenant initialization failed")
  }
  assert_true(pool.release(first))
  let second = acquired_lease(pool, "tenant-b")
  match pool.with_vm(second, fn(vm) { vm.read("main", "secret") }) {
    @moonwren.VmPoolUsed(@moonwren.ProgramFailed(issues, _)) =>
      assert_true(issues[0].message.contains("not loaded"))
    _ => fail("tenant state must not survive isolated release")
  }
  assert_true(pool.release(second))
  let stats = pool.stats()
  assert_eq(stats.capacity, 1)
  assert_eq(stats.active, 0)
  assert_eq(stats.acquisitions, 2)
  assert_eq(stats.recycled, 2)
  pool.close()
}

///|
test "VM pool enforces tenant and capacity limits and rejects stale leases" {
  let pool = @moonwren.VmPool::new(
    @moonwren.VmPoolConfig::isolated(2, 1),
    pooled_test_vm,
  )
  let first = acquired_lease(pool, "tenant-a")
  match pool.acquire("tenant-a") {
    @moonwren.VmPoolAcquired(_) => fail("tenant limit must be enforced")
    @moonwren.VmPoolExhausted(message) =>
      assert_true(message.contains("tenant"))
  }
  let second = acquired_lease(pool, "tenant-b")
  match pool.acquire("tenant-c") {
    @moonwren.VmPoolAcquired(_) => fail("capacity must be enforced")
    @moonwren.VmPoolExhausted(message) => assert_true(message.contains("free"))
  }
  assert_true(pool.invalidate(first))
  assert_true(!pool.release(first))
  assert_true(pool.release(second))
  assert_eq(pool.stats().rejections, 2)
  pool.close()
}

///|
test "reusable VM pool rotates at use limit and across tenants" {
  let pool = @moonwren.VmPool::new(
    @moonwren.VmPoolConfig::new(1, 2, 1, false),
    pooled_test_vm,
  )
  let first = acquired_lease(pool, "same")
  assert_true(pool.release(first))
  assert_eq(pool.stats().recycled, 0)
  let second = acquired_lease(pool, "same")
  assert_true(pool.release(second))
  assert_eq(pool.stats().recycled, 1)
  let third = acquired_lease(pool, "other")
  assert_true(pool.release(third))
  pool.close()
}
