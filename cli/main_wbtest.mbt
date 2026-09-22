///|
/// Whitebox CLI tests: `run` is a pure argv -> stdout-string
/// function, so every assertion pins the complete user-facing
/// output, verdict line included.
test "cli demo prints the hand-traced matching and a stable verdict" {
  @test.assert_eq(
    run(["demo"]),
    "P0 -> R1\nP1 -> R2\nP2 -> R0\ncertificate: STABLE (no blocking pair)",
  )
}

///|
test "cli check re-verifies a tampered claim without running DA" {
  @test.assert_eq(
    run(["check", "1,0,2|0,1,2|0,1,2", "2,1,0|0,2,1|0,1,2", "0,1,2"]),
    "P0 -> R0\nP1 -> R1\nP2 -> R2\ncertificate: UNSTABLE, 4 blocking pair(s): (P0, R1) (P1, R0) (P2, R0) (P2, R1)",
  )
}

///|
test "cli hr renders holders next to the resident-side table" {
  @test.assert_eq(
    run(["hr", "1,0|0,1|0,1|1,0", "0,1,2,3|1,0,2,3", "2,1"]),
    "P0 -> R1\nP1 -> R0\nP2 -> R0\nP3 -> unmatched\nH0 holds: P1, P2\nH1 holds: P0\ncertificate: STABLE (no blocking pair)",
  )
}

///|
test "cli ttc reports the cycle outcome and both audits" {
  @test.assert_eq(
    run(["ttc", "1,2,0|2,0,1|0,1,2", "2,1,0"]),
    "A0 gets good 1\nA1 gets good 2\nA2 gets good 0\naudit: individually rational = yes\naudit: Pareto-clean = yes\n",
  )
}

///|
test "cli parsers reject junk with usage errors" {
  try (parse_ints("0,x") : Array[Int]) catch {
    Usage(_) => ()
  } noraise {
    _ => fail("expected Usage for a non-integer cell")
  }
  try (parse_table("0,1|") : Array[Array[Int]]) catch {
    Usage(_) => ()
  } noraise {
    _ => fail("expected Usage for a trailing empty row")
  }
  try (run(["bogus"]) : String) catch {
    Usage(_) => ()
    // `run` has an open raise type, so the catch must expect any error
    e => fail("expected Usage, got \{e}")
  } noraise {
    _ => fail("expected Usage for an unknown command")
  }
}
