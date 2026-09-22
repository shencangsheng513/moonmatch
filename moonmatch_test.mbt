///|
fn market(
  ps : Array[Array[Int]],
  rs : Array[Array[Int]],
) -> @moonmatch.Preferences raise {
  @moonmatch.Preferences::new(ps, rs) catch {
    e => fail("unexpected error: \{e}")
  }
}

///|
test "deferred acceptance finds the obvious matching in a 2x2 market" {
  let m = market([[0, 1], [1, 0]], [[0, 1], [0, 1]]).deferred_acceptance()
  // P0 gets its first choice R0; P1 then gets R1 unchallenged.
  @test.assert_eq(m.proposer_to_receiver, [0, 1])
  @test.assert_eq(m.receiver_to_proposer, [0, 1])
  @test.assert_eq(m.is_stable(), true)
}

///|
test "deferred acceptance outcome on a hand-computed 3x3 market" {
  // Trace by hand: P0->R1 held; P1->R0 held; P2->R0 beats P1 (R0 ranks
  // P2 first); P1->R1 loses to P0; P1->R2 accepted.
  let m = market([[1, 0, 2], [0, 1, 2], [0, 1, 2]], [
    [2, 1, 0],
    [0, 2, 1],
    [0, 1, 2],
  ]).deferred_acceptance()
  @test.assert_eq(m.proposer_to_receiver, [1, 2, 0])
  @test.assert_eq(m.is_stable(), true)
}

///|
test "more receivers than proposers leaves the least desired receiver empty" {
  let m = market([[0, 1, 2], [2, 1, 0]], [[0, 1], [0, 1], [1, 0]]).deferred_acceptance()
  @test.assert_eq(m.proposer_to_receiver, [0, 2])
  @test.assert_eq(m.receiver_to_proposer, [0, -1, 1])
  @test.assert_eq(m.is_stable(), true)
}

///|
test "more proposers than receivers leaves tail proposers unmatched, stably" {
  let m = market([[0], [0], [0]], [[2, 1, 0]]).deferred_acceptance()
  // Only R0 exists; it holds its favourite proposer P2.
  @test.assert_eq(m.proposer_to_receiver, [-1, -1, 0])
  @test.assert_eq(m.receiver_to_proposer, [2])
  // P0/P1 prefer R0 to nothing, but R0 prefers P2, so no block.
  @test.assert_eq(m.is_stable(), true)
}

///|
test "Preferences::new rejects empty markets" {
  try (@moonmatch.Preferences::new([], [[]]) : @moonmatch.Preferences) catch {
    @moonmatch.Empty => ()
    e => fail("expected Empty, got \{e}")
  } noraise {
    _ => fail("expected Empty")
  }
}

///|
test "Preferences::new rejects ragged rows" {
  try
    (@moonmatch.Preferences::new([[0]], [[0], [1]]) : @moonmatch.Preferences)
  catch {
    @moonmatch.RowLength(@moonmatch.Proposer, 0, 2, 1) => ()
    e => fail("expected RowLength, got \{e}")
  } noraise {
    _ => fail("expected RowLength")
  }
}

///|
test "Preferences::new rejects duplicate and out-of-range entries" {
  try
    (@moonmatch.Preferences::new([[1, 1]], [[0], [0]]) : @moonmatch.Preferences)
  catch {
    @moonmatch.NotPermutation(@moonmatch.Proposer, 0) => ()
    e => fail("expected NotPermutation(duplicate), got \{e}")
  } noraise {
    _ => fail("expected NotPermutation(duplicate)")
  }
  try
    (@moonmatch.Preferences::new([[0, 1]], [[0], [5]]) : @moonmatch.Preferences)
  catch {
    @moonmatch.NotPermutation(@moonmatch.Receiver, 1) => ()
    e => fail("expected NotPermutation(range), got \{e}")
  } noraise {
    _ => fail("expected NotPermutation(range)")
  }
}
