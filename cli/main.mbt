///|
/// moonmatch demo CLI. Market profiles are passed as command-line
/// arguments and every answer is printed to stdout, so the
/// file-free/stdin-free core promise holds on every backend
/// (this toolchain has no file API and no exit-code API either -
/// the `certificate:` line is the machine-readable verdict).
///
/// Profile syntax: rows separated by `|`, integers by `,`, e.g.
/// `1,0,2|0,1,2|0,1,2` is three agents ranking receivers 0..2.
suberror CliError {
  Usage(String)
} derive(Debug)

///|
impl Show for CliError with fn output(self : CliError, logger) {
  match self {
    Usage(msg) => logger.write_string("usage error: \{msg}")
  }
}

///|
let usage : String = "moonmatch <command> [args...]\n  (no args) or `demo`   hand-traced 3x3 market\n  da <proposer-prefs> <receiver-prefs>\n  hr <proposer-prefs> <receiver-prefs> <quotas>\n  ttc <prefs> <endowment>\n  check <proposer-prefs> <receiver-prefs> <claim>\n  cert <proposer-prefs> <receiver-prefs>\n  verify <certificate-json>\nrows separated by '|', integers by ','; -1 in a claim means unmatched.\n`check` never runs an algorithm: it re-verifies someone else's answer.\n`cert` exports a JSON certificate; `verify` checks one without running anything."

///|
fn parse_ints(s : String) -> Array[Int] raise CliError {
  let out = Array(capacity=4)
  for cell in s.split(",") {
    let v = Some(@string.FromStr::from_str(cell)) catch { _ => None }
    match v {
      None => raise Usage("bad integer '\{cell.to_owned()}' in '\{s}'")
      Some(x) => out.push(x)
    }
  }
  if out.length() == 0 {
    raise Usage("empty number list")
  }
  out
}

///|
fn parse_table(s : String) -> Array[Array[Int]] raise CliError {
  let rows = Array(capacity=2)
  for row in s.split("|") {
    let r = row.to_owned()
    if r.length() == 0 {
      raise Usage("empty row in '\{s}' (rows are separated by '|')")
    }
    rows.push(parse_ints(r))
  }
  rows
}

///|
fn render_p2p(p2p : Array[Int]) -> String {
  let mut out = ""
  for p in 0..<p2p.length() {
    let r = p2p[p]
    let line = if r >= 0 { "P\{p} -> R\{r}\n" } else { "P\{p} -> unmatched\n" }
    out = out + line
  }
  out
}

///|
fn verdict_line(blocks : Array[(Int, Int)]) -> String {
  if blocks.length() == 0 {
    "certificate: STABLE (no blocking pair)"
  } else {
    let mut out = "certificate: UNSTABLE, \{blocks.length()} blocking pair(s):"
    for (p, r) in blocks {
      out = out + " (P\{p}, R\{r})"
    }
    out
  }
}

///|
/// Verdict on a delivered JSON blob. Errors are printed, never
/// propagated: a rejected certificate is an ANSWER, not a crash.
fn verify_verdict(blob : String) -> String {
  let maybe_cert = Some(@moonmatch.StabilityCert::from_json_string(blob)) catch {
    _ => None
  }
  match maybe_cert {
    None => "verify: REJECTED, certificate is not parseable JSON"
    Some(cert) => {
      let mut verdict = "verify: ACCEPTED (every tempting pair has an honest witness)"
      cert.verify() catch {
        e => verdict = "verify: REJECTED: \{e}"
      }
      verdict
    }
  }
}

///|
fn run(argv : Array[String]) -> String raise {
  match argv.length() {
    0 => run(["demo"])
    1 if argv[0] == "demo" || argv[0] == "help" =>
      run(["da", "1,0,2|0,1,2|0,1,2", "2,1,0|0,2,1|0,1,2"])
    n if n >= 3 && argv[0] == "da" => {
      let prefs = @moonmatch.Preferences::new(
        parse_table(argv[1]),
        parse_table(argv[2]),
      )
      let m = prefs.deferred_acceptance()
      render_p2p(m.proposer_to_receiver) + verdict_line(m.blocking_pairs())
    }
    n if n >= 4 && argv[0] == "hr" => {
      let prefs = @moonmatch.Preferences::new(
        parse_table(argv[1]),
        parse_table(argv[2]),
      )
      let a = prefs.hospital_residents(parse_ints(argv[3]))
      let mut out = render_p2p(a.proposer_to_receiver)
      for h in 0..<a.receiver_holders.length() {
        let holders = a.receiver_holders[h]
        let mut names = ""
        for i in 0..<holders.length() {
          names = names + (if i > 0 { ", " } else { "" }) + "P\{holders[i]}"
        }
        let line = if holders.length() == 0 {
          "H\{h} holds: nobody\n"
        } else {
          "H\{h} holds: \{names}\n"
        }
        out = out + line
      }
      out + verdict_line(a.blocking_pairs())
    }
    n if n >= 3 && argv[0] == "ttc" => {
      let market = @moonmatch.Market::new(
        parse_table(argv[1]),
        parse_ints(argv[2]),
      )
      let alloc = market.top_trading_cycles()
      let size = alloc.length()
      let mut out = ""
      for a in 0..<size {
        out = out + "A\{a} gets good \{alloc[a]}\n"
      }
      let ir = if market.is_individually_rational(alloc) { "yes" } else { "no" }
      let core = if size <= 7 {
        let dominators = market.pareto_dominators(alloc).length()
        if dominators == 0 {
          "audit: Pareto-clean = yes"
        } else {
          "audit: Pareto-clean = no (\{dominators} dominating allocation(s))"
        }
      } else {
        "audit: Pareto scan skipped for n > 7 (exhaustive, exponential)"
      }
      out + "audit: individually rational = \{ir}\n" + core + "\n"
    }
    n if n >= 4 && argv[0] == "check" => {
      let prefs = @moonmatch.Preferences::new(
        parse_table(argv[1]),
        parse_table(argv[2]),
      )
      let m = prefs.matching_from(parse_ints(argv[3]))
      render_p2p(m.proposer_to_receiver) + verdict_line(m.blocking_pairs())
    }
    n if n >= 3 && argv[0] == "cert" => {
      let prefs = @moonmatch.Preferences::new(
        parse_table(argv[1]),
        parse_table(argv[2]),
      )
      "certificate: \{prefs.deferred_acceptance().certificate().to_json_string()}"
    }
    n if n >= 2 && argv[0] == "verify" => verify_verdict(argv[1])
    _ => raise Usage("unrecognized arguments; here is the help:\n\{usage}")
  }
}

///|
fn main {
  let argv = @env.args()[1:].to_owned()
  println(
    run(argv) catch {
      Usage(msg) => "error: \{msg}\n\n\{usage}"
      e => "error: \{e}"
    },
  )
}
