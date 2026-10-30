///|
#cfg(target="js")
extern "js" fn install_web_sdk(
  run_source : (String, Int32) -> String,
  evaluate_source : (String, Int32) -> String,
) -> Unit =
  #| (runSource, evaluateSource) => {
  #|   const normalizeLimit = (value) => Number.isSafeInteger(value) && value > 0 ? value : 1000000;
  #|   globalThis.MoonWrenCore = Object.freeze({
  #|     version: "0.9.2",
  #|     runText(source, options = {}) {
  #|       return runSource(String(source), normalizeLimit(options.maxSteps));
  #|     },
  #|     evaluate(source, options = {}) {
  #|       return JSON.parse(evaluateSource(String(source), normalizeLimit(options.maxSteps)));
  #|     }
  #|   });
  #|   if (typeof document === "undefined") return;
  #|   const run = document.getElementById("run");
  #|   const source = document.getElementById("source");
  #|   const output = document.getElementById("output");
  #|   const status = document.getElementById("status");
  #|   const picker = document.getElementById("example");
  #|   if (!run || !source || !output || !status || !picker) return;
  #|   const initial = source.value;
  #|   const examples = {
  #|     sum: initial,
  #|     collections: 'var values = [3, 1, 2]\nvalues.sort()\nSystem.print(values)\nvar map = {"answer": 42}\nSystem.print(map["answer"])',
  #|     fiber: 'var worker = Fiber.new {\n  System.print("started")\n  Fiber.yield("paused")\n  return "finished"\n}\nSystem.print(worker.call())\nSystem.print(worker.call())',
  #|     unicode: 'var text = "你好, MoonWren"\nSystem.print(text.count)\nSystem.print(text.bytes.count)\nSystem.print(text[0])'
  #|   };
  #|   const execute = () => {
  #|     const started = performance.now();
  #|     output.textContent = globalThis.MoonWrenCore.runText(source.value);
  #|     status.textContent = "Finished in " + (performance.now() - started).toFixed(1) + " ms";
  #|   };
  #|   run.addEventListener("click", execute);
  #|   document.getElementById("reset").addEventListener("click", () => { source.value = initial; picker.value = "sum"; history.replaceState(null, "", location.pathname + location.search); execute(); });
  #|   picker.addEventListener("change", () => { source.value = examples[picker.value]; execute(); });
  #|   source.addEventListener("keydown", (event) => { if ((event.ctrlKey || event.metaKey) && event.key === "Enter") { event.preventDefault(); execute(); } });
  #|   document.getElementById("share").addEventListener("click", async () => {
  #|     const url = new URL(location.href); url.hash = encodeURIComponent(source.value);
  #|     history.replaceState(null, "", url);
  #|     try { await navigator.clipboard.writeText(url.href); status.textContent = "Share link copied"; }
  #|     catch (_) { status.textContent = "Share link is ready in the address bar"; }
  #|   });
  #|   if (location.hash.length > 1) { try { source.value = decodeURIComponent(location.hash.slice(1)); picker.value = ""; } catch (_) {} }
  #|   execute();
  #| }

///|
#cfg(target="js")
fn render(source : String, max_steps : Int32) -> String {
  match @moonwren.run_with_limit(source, max_steps) {
    @moonwren.ProgramCompleted(value, output) => {
      let lines : Array[String] = []
      for line in output {
        lines.push(line)
      }
      lines.push("=> " + value.to_text())
      lines.join("\n")
    }
    @moonwren.ProgramFailed(issues, output) => {
      let lines : Array[String] = []
      for line in output {
        lines.push(line)
      }
      for issue in issues {
        lines.push(issue.render("playground"))
      }
      lines.join("\n")
    }
  }
}

///|
#cfg(target="js")
fn evaluate_json(source : String, max_steps : Int32) -> String {
  let document : Map[String, Json] = Map([])
  match @moonwren.run_with_limit(source, max_steps) {
    @moonwren.ProgramCompleted(value, output) => {
      let output_json : Array[Json] = []
      for line in output {
        output_json.push(Json::string(line))
      }
      document["ok"] = Json::boolean(true)
      document["value"] = Json::string(value.to_text())
      document["output"] = Json::array(output_json)
      document["diagnostics"] = Json::array([])
    }
    @moonwren.ProgramFailed(issues, output) => {
      let diagnostics : Array[Json] = []
      let output_json : Array[Json] = []
      for line in output {
        output_json.push(Json::string(line))
      }
      for issue in issues {
        let entry : Map[String, Json] = Map([])
        entry["message"] = Json::string(issue.message)
        entry["rendered"] = Json::string(issue.render("sdk"))
        entry["line"] = Json::number(issue.span.start.line.to_double())
        entry["column"] = Json::number(issue.span.start.column.to_double())
        diagnostics.push(Json::object(entry))
      }
      document["ok"] = Json::boolean(false)
      document["value"] = Json::null()
      document["output"] = Json::array(output_json)
      document["diagnostics"] = Json::array(diagnostics)
    }
  }
  Json::object(document).stringify()
}

///|
#cfg(target="js")
fn main {
  install_web_sdk(render, evaluate_json)
}

///|
#cfg(not(target="js"))
fn main {
  ignore(@moonwren.run("null"))
  println("Build this package with --target js and open web/index.html.")
}
