///|
/// moon-jsonq CLI (`mq`) — a real jq-like command line tool.
///
///   echo '{"name":"Yan","score":95}' | mq '.name'
///   # "Yan"
///   echo '[3,1,2]' | mq 'sort'
///   # [1,2,3]
///   mq '.users[].name' examples/data.json
///   mq -r '.name' < input.json
///   echo '{"a":null}' | mq '.a // "x"'
///
/// Build a native binary with:
///   moon build --target native main
///   # -> _build/native/debug/build/main/main.exe
/// Run it without building with:
///   echo '{"name":"Yan"}' | moon run --target native main -- '.name'
///
/// Why `async fn main` and native-only:
/// stdin and files in this MoonBit version (0.1.20261119) live
/// in the experimental async packages `@stdio` and `@fs`
/// (see `moonbitlang/core/async/README.md` and the `filter`
/// test program in core, which uses the same pattern:
/// `async fn main`, `@env.args()`, `@stdio.stdin.text.read_all()`).
/// The library in `lib/` stays pure and Wasm-compatible;
/// only this CLI package is native-only
/// (`supported_targets = "-all+native"` in `moon.pkg`).
///
/// Exit codes: 0 ok, 1 bad filter / bad JSON / unreadable
/// file, 2 usage error (unknown flag, missing argument).

///|
const USAGE : String = "Usage: mq [options] [filter] [file ...]\n" +
  "\n" +
  "A jq-inspired JSON query tool, written in MoonBit.\n" +
  "Reads JSON from stdin or from files, applies the filter,\n" +
  "and prints one JSON value per line (like jq).\n" +
  "\n" +
  "Options:\n" +
  "  -h, --help           show this help and exit\n" +
  "  --version            show the version and exit\n" +
  "  -r, --raw-output     print string results without quotes\n" +
  "  -c, --compact-output print compact JSON (the default)\n" +
  "  --pretty             print indented JSON (2 spaces)\n" +
  "  -n, --null-input     use null as the input, do not read stdin\n" +
  "  -s, --slurp          read all JSON values into one array first\n" +
  "  -f, --from-file FILE read the filter from FILE\n" +
  "\n" +
  "Examples:\n" +
  "  echo '{\"name\":\"Yan\"}' | mq '.name'\n" +
  "  echo '[3,1,2]' | mq 'sort'\n" +
  "  echo '{\"users\":[{\"name\":\"a\"}]}' | mq '.users[].name'\n" +
  "  mq -r '.name' data.json\n" +
  "  echo '1\\n2\\n3' | mq -s 'add'\n"

///|
async fn main {
  let args = @env.args()[1:]
  let mut raw_output = false
  let mut pretty = false
  let mut null_input = false
  let mut slurp = false
  let mut filter_file : String? = None
  let positionals : Array[String] = []
  let mut i = 0
  let mut end_of_flags = false
  while i < args.length() {
    let a = args[i]
    if end_of_flags {
      positionals.push(a)
    } else if a == "--" {
      end_of_flags = true
    } else if a == "-h" || a == "--help" {
      println(USAGE)
      @env.exit(0)
    } else if a == "--version" {
      println("mq 0.2.0 (moon-jsonq, MoonBit port of jq 1.7 core)")
      @env.exit(0)
    } else if a == "-r" || a == "--raw-output" {
      raw_output = true
    } else if a == "-c" || a == "--compact-output" {
      pretty = false
    } else if a == "--pretty" {
      pretty = true
    } else if a == "-n" || a == "--null-input" {
      null_input = true
    } else if a == "-s" || a == "--slurp" {
      slurp = true
    } else if a == "-f" || a == "--from-file" {
      i = i + 1
      if i >= args.length() {
        eprintln("mq: --from-file needs a file name")
        eprintln(USAGE)
        @env.exit(2)
      }
      filter_file = Some(args[i])
    } else if a.has_prefix("-") && a.length() > 1 {
      eprintln("mq: unknown option '" + a + "'")
      eprintln(USAGE)
      @env.exit(2)
    } else {
      positionals.push(a)
    }
    i = i + 1
  }

  // Filter text: from -f, from the first positional, or ".".
  let filter_src = match filter_file {
    Some(path) =>
      match read_file_text(path) {
        Ok(text) => text
        Err(msg) => {
          eprintln("mq: " + msg)
          @env.exit(1)
        }
      }
    None =>
      match positionals {
        [] => "."
        [first, .. _rest] => first
      }
  }
  let input_files : Array[String] = if positionals.length() <= 1 {
    []
  } else {
    [
      for x in positionals[1:] => x
    ]
  }
  // If the filter came from -f, every positional is a file.
  let files = match filter_file {
    Some(_) => positionals
    None => input_files
  }
  let input_files = files

  let filter = match @lib.parse_filter(filter_src) {
    Ok(f) => f
    Err(msg) => {
      eprintln("mq: bad filter: " + msg)
      @env.exit(1)
    }
  }

  // Inputs: null, files, or stdin.
  if null_input {
    run_filter(filter, @lib.Null, raw_output, pretty)
    @env.exit(0)
  }
  if input_files.length() > 0 {
    for path in input_files {
      match read_file_text(path) {
        Ok(text) => run_on_text(filter, text, slurp, raw_output, pretty)
        Err(msg) => {
          eprintln("mq: " + msg)
          @env.exit(1)
        }
      }
    }
    @env.exit(0)
  }
  let text = @stdio.stdin.text.read_all() catch {
    _ => {
      eprintln("mq: could not read stdin")
      @env.exit(1)
    }
  }
  run_on_text(filter, text, slurp, raw_output, pretty)
  @env.exit(0)
}

///|
/// Read a whole file as text, or return an error message.
async fn read_file_text(path : String) -> Result[String, String] {
  try {
    let file = @fs.open(path, mode=@fs.ReadOnly)
    let text = file.text.read_all()
    file.close()
    Ok(text)
  } catch {
    _ => Err("could not read file '" + path + "'")
  }
}

///|
/// Parse one input document (or several, if the text holds
/// more than one JSON value) and run the filter on each.
fn run_on_text(
  filter : @lib.Filter,
  text : String,
  slurp : Bool,
  raw_output : Bool,
  pretty : Bool,
) -> Unit {
  if text.trim().length() == 0 {
    // Empty input, like jq: no output, exit 0.
    return
  }
  if slurp {
    let values = match @lib.parse_json(text) {
      Ok(v) => [v]
      Err(_) =>
        match @lib.parse_json_stream(text) {
          Ok(vs) => vs
          Err(msg) => {
            eprintln("mq: " + msg)
            @env.exit(1)
          }
        }
    }
    run_filter(filter, @lib.Arr(values), raw_output, pretty)
    return
  }
  match @lib.parse_json(text) {
    Ok(v) => run_filter(filter, v, raw_output, pretty)
    Err(_) =>
      // Maybe several values, one per line (NDJSON).
      match @lib.parse_json_stream(text) {
        Ok(values) =>
          for v in values {
            run_filter(filter, v, raw_output, pretty)
          }
        Err(msg) => {
          eprintln("mq: " + msg)
          @env.exit(1)
        }
      }
  }
}

///|
/// Run the filter on one input value and print each output
/// on its own line.
fn run_filter(
  filter : @lib.Filter,
  input : @lib.JVal,
  raw_output : Bool,
  pretty : Bool,
) -> Unit {
  for out in @lib.eval(filter, input) {
    if pretty {
      println(out.to_pretty_string())
    } else if raw_output {
      match out {
        @lib.Str(s) => println(s)
        _ => println(out.to_string())
      }
    } else {
      println(out.to_string())
    }
  }
}
