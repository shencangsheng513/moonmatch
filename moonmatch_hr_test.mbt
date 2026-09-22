///|
test "all-ones quotas reproduce the one-to-one matching exactly" {
  let ps = [[1, 0, 2], [0, 1, 2], [0, 1, 2]]
  let rs = [[2, 1, 0], [0, 2, 1], [0, 1, 2]]
  let da = market(ps, rs).deferred_acceptance()
  let hr = market(ps, rs).hospital_residents([1, 1, 1]) catch {
    e => fail("unexpected error: \{e}")
  }
  @test.assert_eq(hr.proposer_to_receiver, da.proposer_to_receiver)
  @test.assert_eq(hr.is_stable(), true)
}

///|
test "hospital/residents outcome on a hand-computed capacity market" {
  // 4 residents, hospital 0 has 2 seats, hospital 1 has 1.
  // Trace: everyone proposes to first choice; H0 holds its two best of
  // {P0,P1,P3} = {P3,P1} and evicts P0; P0 -> H1 beats P2; P2 -> H0
  // beats P1; P1 -> H1 loses and stays unmatched.
  let hr = market([[0, 1], [0, 1], [1, 0], [0, 1]], [[3, 2, 1, 0], [0, 2, 1, 3]]).hospital_residents([
      2, 1,
    ],
  ) catch {
    e => fail("unexpected error: \{e}")
  }
  @test.assert_eq(hr.proposer_to_receiver, [1, -1, 0, 0])
  // seats filled exactly: H0 has 2 holders, H1 has 1
  @test.assert_eq(
    [hr.receiver_holders[0].length(), hr.receiver_holders[1].length()],
    [2, 1],
  )
  @test.assert_eq(hr.is_stable(), true)
}

///|
test "scarce capacity leaves residents unmatched without blocking" {
  // one seat, three claimants: the hospital picks its favourite and the
  // others have nowhere better to go, so stability still holds.
  let hr = market([[0], [0], [0]], [[2, 1, 0]]).hospital_residents([1]) catch {
    e => fail("unexpected error: \{e}")
  }
  @test.assert_eq(hr.proposer_to_receiver, [-1, -1, 0])
  @test.assert_eq(hr.is_stable(), true)
}

///|
test "quota table must match the market shape" {
  try
    (
      market([[0, 1], [1, 0]], [[0, 1], [0, 1]]).hospital_residents([1]) :
      @moonmatch.HRAssignment)
  catch {
    @moonmatch.QuotaLength(1, 2) => ()
    e => fail("expected QuotaLength, got \{e}")
  } noraise {
    _ => fail("expected QuotaLength")
  }
  try
    (
      market([[0, 1], [1, 0]], [[0, 1], [0, 1]]).hospital_residents([0, 1]) :
      @moonmatch.HRAssignment)
  catch {
    @moonmatch.NonPositiveQuota(0, 0) => ()
    e => fail("expected NonPositiveQuota, got \{e}")
  } noraise {
    _ => fail("expected NonPositiveQuota")
  }
}
