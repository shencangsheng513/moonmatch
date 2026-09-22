///|
fn tmarket(
  prefs : Array[Array[Int]],
  endowment : Array[Int],
) -> @moonmatch.Market raise {
  @moonmatch.Market::new(prefs, endowment) catch {
    e => fail("unexpected error: \{e}")
  }
}

///|
test "a three-agent trade cycle executes in one round" {
  // A0 wants A1's good, A1 wants A2's, A2 wants A0's: one closed loop.
  let m = tmarket([[1, 2, 0], [2, 0, 1], [0, 1, 2]], [0, 1, 2])
  let alloc = m.top_trading_cycles()
  @test.assert_eq(alloc, [1, 2, 0])
  @test.assert_eq(m.is_individually_rational(alloc), true)
  @test.assert_eq(m.pareto_dominators(alloc).length(), 0)
}

///|
test "self-loops trade first and leftovers keep their own good" {
  let m = tmarket([[0, 1], [0, 1]], [0, 1])
  let alloc = m.top_trading_cycles()
  // A0 keeps h0 immediately; A1's favourite is then off-market, so A1
  // is left with its own h1.
  @test.assert_eq(alloc, [0, 1])
  @test.assert_eq(m.is_individually_rational(alloc), true)
}

///|
test "mixed cycle and self-loop resolve together (hand trace)" {
  // owners: h0->A2, h1->A1, h2->A0. Round 1: A2 points at h0 (self);
  // A0 points at h1 (owner A1); A1 points at h2 (owner A0) -> cycle
  // (A0 A1). Both trades happen the same round: alloc [1, 2, 0].
  let m = tmarket([[1, 0, 2], [2, 1, 0], [0, 1, 2]], [2, 1, 0])
  let alloc = m.top_trading_cycles()
  @test.assert_eq(alloc, [1, 2, 0])
  @test.assert_eq(m.is_individually_rational(alloc), true)
  @test.assert_eq(m.pareto_dominators(alloc).length(), 0)
}

///|
test "a worse endowment is still off-limits: IR rejects manual harm" {
  // Sanity for the audit itself: hand an allocation that gives A0 its
  // worst good and confirm individual rationality says no.
  let m = tmarket([[0, 1], [1, 0]], [0, 1])
  @test.assert_eq(m.is_individually_rational([1, 0]), false)
  // ...while TTC's own answer passes and is genuinely Pareto-clean:
  let alloc = m.top_trading_cycles()
  @test.assert_eq(alloc, [0, 1])
  @test.assert_eq(m.pareto_dominators(alloc).length(), 0)
}

///|
test "Market::new gates rows and endowment" {
  try (@moonmatch.Market::new([], []) : @moonmatch.Market) catch {
    @moonmatch.MarketError::Empty => ()
    e => fail("expected Empty, got \{e}")
  } noraise {
    _ => fail("expected Empty")
  }
  try
    (@moonmatch.Market::new([[0, 0], [1, 0]], [0, 1]) : @moonmatch.Market)
  catch {
    @moonmatch.RowNotPerm(0) => ()
    e => fail("expected RowNotPerm, got \{e}")
  } noraise {
    _ => fail("expected RowNotPerm")
  }
  try
    (@moonmatch.Market::new([[0, 1], [1, 0]], [0]) : @moonmatch.Market)
  catch {
    @moonmatch.EndowmentLength(1, 2) => ()
    e => fail("expected EndowmentLength, got \{e}")
  } noraise {
    _ => fail("expected EndowmentLength")
  }
  try
    (@moonmatch.Market::new([[0, 1], [1, 0]], [1, 1]) : @moonmatch.Market)
  catch {
    @moonmatch.EndowmentNotPerm => ()
    e => fail("expected EndowmentNotPerm, got \{e}")
  } noraise {
    _ => fail("expected EndowmentNotPerm")
  }
}
