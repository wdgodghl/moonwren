///|
pub(all) struct VmPoolConfig {
  size : Int
  max_uses_per_vm : Int
  max_leases_per_tenant : Int
  reset_on_release : Bool
}

///|
pub fn VmPoolConfig::isolated(
  size : Int,
  max_leases_per_tenant : Int,
) -> VmPoolConfig {
  {
    size: if size > 0 {
      size
    } else {
      1
    },
    max_uses_per_vm: 1,
    max_leases_per_tenant: if max_leases_per_tenant > 0 {
      max_leases_per_tenant
    } else {
      1
    },
    reset_on_release: true,
  }
}

///|
pub fn VmPoolConfig::new(
  size : Int,
  max_uses_per_vm : Int,
  max_leases_per_tenant : Int,
  reset_on_release : Bool,
) -> VmPoolConfig {
  {
    size: if size > 0 {
      size
    } else {
      1
    },
    max_uses_per_vm: if max_uses_per_vm > 0 {
      max_uses_per_vm
    } else {
      1
    },
    max_leases_per_tenant: if max_leases_per_tenant > 0 {
      max_leases_per_tenant
    } else {
      1
    },
    reset_on_release,
  }
}

///|
pub struct VmPoolLease {
  pool_identity : Int
  entry_index : Int
  token : Int
  tenant : String
}

///|
pub(all) enum VmPoolAcquireResult {
  VmPoolAcquired(VmPoolLease)
  VmPoolExhausted(String)
}

///|
pub(all) enum VmPoolUseResult[T] {
  VmPoolUsed(T)
  VmPoolLeaseRejected(String)
}

///|
pub(all) struct VmPoolStats {
  capacity : Int
  active : Int
  created : Int
  recycled : Int
  acquisitions : Int
  rejections : Int
}

///|
pub struct VmPoolEntry {
  mut vm : Vm
  mut busy : Bool
  mut token : Int
  mut uses : Int
  mut tenant : String?
}

///|
let vm_pool_identities : Array[Unit] = []

///|
/// Bounded VM pool with per-tenant concurrency controls and optional reset on
/// every release. The isolated configuration is the safe default for mutually
/// untrusted tenants.
pub struct VmPool {
  identity : Int
  config : VmPoolConfig
  factory : () -> Vm
  entries : Array[VmPoolEntry]
  mut closed : Bool
  mut next_token : Int
  mut created : Int
  mut recycled : Int
  mut acquisitions : Int
  mut rejections : Int
}

///|
pub fn VmPool::new(config : VmPoolConfig, factory : () -> Vm) -> VmPool {
  let identity = vm_pool_identities.length()
  vm_pool_identities.push(())
  let entries : Array[VmPoolEntry] = []
  for _index = 0; _index < config.size; _index = _index + 1 {
    entries.push({
      vm: factory(),
      busy: false,
      token: 0,
      uses: 0,
      tenant: None,
    })
  }
  {
    identity,
    config,
    factory,
    entries,
    closed: false,
    next_token: 1,
    created: entries.length(),
    recycled: 0,
    acquisitions: 0,
    rejections: 0,
  }
}

///|
fn VmPool::active_for_tenant(self : VmPool, tenant : String) -> Int {
  let mut active = 0
  for entry in self.entries {
    if entry.busy && entry.tenant == Some(tenant) {
      active = active + 1
    }
  }
  active
}

///|
fn VmPool::replace_entry(self : VmPool, entry : VmPoolEntry) -> Unit {
  entry.vm.close()
  entry.vm = (self.factory)()
  entry.uses = 0
  entry.tenant = None
  self.created = self.created + 1
  self.recycled = self.recycled + 1
}

///|
pub fn VmPool::acquire(self : VmPool, tenant : String) -> VmPoolAcquireResult {
  if self.closed {
    self.rejections = self.rejections + 1
    return VmPoolExhausted("VM pool is closed")
  }
  if tenant.length() == 0 {
    self.rejections = self.rejections + 1
    return VmPoolExhausted("tenant id is required")
  }
  if self.active_for_tenant(tenant) >= self.config.max_leases_per_tenant {
    self.rejections = self.rejections + 1
    return VmPoolExhausted("tenant lease limit reached")
  }
  for index = 0; index < self.entries.length(); index = index + 1 {
    let entry = self.entries[index]
    if !entry.busy {
      if !self.config.reset_on_release &&
        entry.tenant is Some(previous) &&
        previous != tenant {
        self.replace_entry(entry)
      }
      let token = self.next_token
      self.next_token = self.next_token + 1
      entry.busy = true
      entry.token = token
      entry.tenant = Some(tenant)
      self.acquisitions = self.acquisitions + 1
      return VmPoolAcquired({
        pool_identity: self.identity,
        entry_index: index,
        token,
        tenant,
      })
    }
  }
  self.rejections = self.rejections + 1
  VmPoolExhausted("VM pool has no free lease")
}

///|
fn VmPool::valid_entry(self : VmPool, lease : VmPoolLease) -> VmPoolEntry? {
  if self.closed ||
    lease.pool_identity != self.identity ||
    lease.entry_index < 0 ||
    lease.entry_index >= self.entries.length() {
    return None
  }
  let entry = self.entries[lease.entry_index]
  if !entry.busy ||
    entry.token != lease.token ||
    entry.tenant != Some(lease.tenant) {
    None
  } else {
    Some(entry)
  }
}

///|
/// Execute one host operation against a validated lease. The callback should
/// not retain the VM after it returns.
pub fn[T] VmPool::with_vm(
  self : VmPool,
  lease : VmPoolLease,
  operation : (Vm) -> T,
) -> VmPoolUseResult[T] {
  match self.valid_entry(lease) {
    Some(entry) => VmPoolUsed(operation(entry.vm))
    None => VmPoolLeaseRejected("stale or foreign VM pool lease")
  }
}

///|
/// Release a healthy lease. Isolated pools immediately replace its VM; reusable
/// pools replace it at the configured use limit.
pub fn VmPool::release(self : VmPool, lease : VmPoolLease) -> Bool {
  let entry = match self.valid_entry(lease) {
    Some(value) => value
    None => return false
  }
  entry.busy = false
  entry.uses = entry.uses + 1
  if self.config.reset_on_release || entry.uses >= self.config.max_uses_per_vm {
    self.replace_entry(entry)
  }
  true
}

///|
/// Release and unconditionally destroy the leased VM after a runtime failure or
/// suspected tenant contamination.
pub fn VmPool::invalidate(self : VmPool, lease : VmPoolLease) -> Bool {
  let entry = match self.valid_entry(lease) {
    Some(value) => value
    None => return false
  }
  entry.busy = false
  self.replace_entry(entry)
  true
}

///|
pub fn VmPool::stats(self : VmPool) -> VmPoolStats {
  let mut active = 0
  for entry in self.entries {
    if entry.busy {
      active = active + 1
    }
  }
  {
    capacity: self.entries.length(),
    active,
    created: self.created,
    recycled: self.recycled,
    acquisitions: self.acquisitions,
    rejections: self.rejections,
  }
}

///|
pub fn VmPool::close(self : VmPool) -> Unit {
  if self.closed {
    return
  }
  for entry in self.entries {
    entry.vm.close()
    entry.busy = false
  }
  self.closed = true
}
