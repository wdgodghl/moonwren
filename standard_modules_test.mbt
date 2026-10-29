///|
test "standard JSON module parses nested values and stringifies them" {
  let source =
    #|import "moon/json" for Json
    #|var value = Json.parse("{\"name\":\"月\",\"items\":[1,true,null]}")
    #|System.print(value["name"])
    #|System.print(value["items"][1])
    #|Json.stringify(value)
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(value, output) => {
      assert_eq(output, ["月", "true"])
      assert_eq(
        value,
        @moonwren.Value::string("{\"name\":\"月\",\"items\":[1,true,null]}"),
      )
    }
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "standard JSON module rejects invalid data and cycles" {
  match @moonwren.run("import \"moon/json\" for Json\nJson.parse(\"[1,]\")\n") {
    @moonwren.ProgramCompleted(_, _) => fail("invalid JSON must fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_true(issues[0].message.contains("invalid JSON"))
  }
  let cyclic =
    #|import "moon/json" for Json
    #|var value = []
    #|value.add(value)
    #|Json.stringify(value)
  match @moonwren.run(cyclic) {
    @moonwren.ProgramCompleted(_, _) => fail("cycles must fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_true(issues[0].message.contains("cycle"))
  }
}

///|
test "base64 URL and name UUID modules are deterministic and portable" {
  let source =
    #|import "moon/base64" for Base64
    #|import "moon/url" for Url
    #|import "moon/uuid" for Uuid
    #|System.print(Base64.encode("Moon月"))
    #|System.print(Base64.decode("TW9vbuaciA=="))
    #|System.print(Url.encodeComponent("a b/月"))
    #|System.print(Url.decodeComponent("a%20b%2F%E6%9C%88"))
    #|var first = Uuid.fromName("example", "answer")
    #|System.print(first == Uuid.fromName("example", "answer"))
    #|System.print(first)
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, output) =>
      assert_eq(output, [
        "TW9vbuaciA==", "Moon月", "a%20b%2F%E6%9C%88", "a b/月", "true", "e17e0b0a-1733-8a51-84eb-0b07e480c533",
      ])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "HTTP module yields an auditable scheduler request" {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing \{name}") },
    [],
    [],
  )
  let source =
    #|import "moon/http" for Http
    #|var worker = Fn.new { Http.get("https://example.test/data") }
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let handle = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(value) => value
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let scheduler = vm.new_scheduler(4)
  match scheduler.spawn(handle) {
    @moonwren.VmSchedulerSpawned(_) => ()
    @moonwren.VmSchedulerSpawnFailed(issue) => fail(issue.message)
  }
  match scheduler.poll() {
    @moonwren.VmSchedulerExternalRequest(_, request, _) =>
      match scheduler.snapshot_request(request) {
        Some(@moonwren.ForeignMap(entries)) => {
          let mut kind = ""
          let mut url = ""
          for entry in entries {
            match (entry.key, entry.value) {
              (
                @moonwren.ForeignString("$moonwren"),
                @moonwren.ForeignString(value),
              ) => kind = value
              (@moonwren.ForeignString("url"), @moonwren.ForeignString(value)) =>
                url = value
              _ => ()
            }
          }
          assert_eq(kind, "http")
          assert_eq(url, "https://example.test/data")
        }
        _ => fail("HTTP request must have a host-owned Map snapshot")
      }
    _ => fail("HTTP request must be visible to the host")
  }
  scheduler.close()
  ignore(vm.release(handle))
  vm.close()
}
