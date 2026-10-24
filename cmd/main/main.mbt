///|
fn demo_source() -> String {
  "var total = 0\n" +
  "for (current in 1..10) {\n" +
  "  total = total + current\n" +
  "}\n" +
  "System.print(total)\n"
}

///|
fn file_candidate(path : String) -> String {
  let value : @path.Path = path
  if value.extname().length() == 0 {
    path + ".wren"
  } else {
    path
  }
}

///|
fn canonical_path(path : String) -> String {
  let value : @path.Path = file_candidate(path)
  value.resolve().to_string()
}

///|
fn read_source(path : String) -> String? {
  let source = @fs.read_file_to_string(path) catch { _ => return None }
  Some(source)
}

///|
fn resolve_import_path(importer : String, specifier : String) -> String {
  let requested : @path.Path = file_candidate(specifier)
  let combined = if requested.is_absolute() {
    requested
  } else {
    let parent : @path.Path = importer
    parent.dirname().join(requested)
  }
  combined.resolve().to_string()
}

///|
fn file_loader(
  importer : String,
  specifier : String,
) -> @moonwren.ModuleLoadResult {
  let resolved = resolve_import_path(importer, specifier)
  match read_source(resolved) {
    Some(source) => @moonwren.ModuleLoaded(resolved, source)
    None =>
      @moonwren.ModuleLoadFailed(
        "cannot load module '\{specifier}' resolved as '\{resolved}'",
      )
  }
}

///|
fn print_result(
  result : @moonwren.ProgramRunResult,
  fallback_source : String,
) -> Int {
  match result {
    ProgramCompleted(_, output) => {
      for line in output {
        println(line)
      }
      0
    }
    ProgramFailed(diagnostics, output) => {
      for line in output {
        println(line)
      }
      for diagnostic in diagnostics {
        println(diagnostic.render(fallback_source))
      }
      if diagnostics.length() == 0 {
        70
      } else {
        match diagnostics[0].phase {
          Scan | Parse | Resolve => 65
          Runtime => 70
        }
      }
    }
  }
}

///|
fn main {
  let arguments = @env.args()
  if arguments.length() <= 1 {
    @sys.exit(print_result(@moonwren.run(demo_source()), "<demo>"))
  } else if arguments[1] == "--eval" {
    if arguments.length() <= 2 {
      println("usage: moonwren --eval <source>")
      @sys.exit(64)
    } else {
      @sys.exit(print_result(@moonwren.run(arguments[2]), "<eval>"))
    }
  } else {
    let entry = canonical_path(arguments[1])
    match read_source(entry) {
      None => {
        println("cannot read source file: \{entry}")
        @sys.exit(66)
      }
      Some(source) =>
        @sys.exit(
          print_result(
            @moonwren.run_with_loader(entry, source, 20000000, file_loader),
            entry,
          ),
        )
    }
  }
}
