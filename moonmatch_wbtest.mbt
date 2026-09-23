///|
/// Whitebox: error constructors are read-only outside the package
/// (`pub suberror` only opens matching), so pinning Show wording
/// has to happen inside it.
test "ProfileError Show texts are stable user-facing strings" {
  // Error messages are CLI output; pin the full wording so renames break
  // tests (this core has no String::contains, so equality is the check).
  @test.assert_eq(
    ProfileError::Empty.to_string(),
    "a market needs at least one proposer and one receiver",
  )
  @test.assert_eq(
    RowLength(Proposer, 2, 3, 1).to_string(),
    "proposer preference row 2 has 1 entries, expected 3",
  )
  @test.assert_eq(
    RowLength(Receiver, 0, 2, 5).to_string(),
    "receiver preference row 0 has 5 entries, expected 2",
  )
  @test.assert_eq(
    NotPermutation(Proposer, 1).to_string(),
    "proposer preference row 1 must rank every counterparty exactly once",
  )
  @test.assert_eq(
    NotPermutation(Receiver, 0).to_string(),
    "receiver preference row 0 must rank every counterparty exactly once",
  )
}

///|
test "QuotaError Show texts are stable user-facing strings" {
  @test.assert_eq(QuotaLength(1, 2).to_string(), "got 1 quotas for 2 hospitals")
  @test.assert_eq(
    NonPositiveQuota(0, 0).to_string(),
    "hospital 0 has quota 0, quotas must be positive",
  )
  @test.assert_eq(
    NonPositiveQuota(3, -2).to_string(),
    "hospital 3 has quota -2, quotas must be positive",
  )
}

///|
test "MarketError Show texts are stable user-facing strings" {
  @test.assert_eq(
    MarketError::Empty.to_string(),
    "a housing market needs at least one agent",
  )
  @test.assert_eq(
    RowNotPerm(2).to_string(),
    "agent 2 preference row must rank every good exactly once",
  )
  @test.assert_eq(
    EndowmentLength(1, 2).to_string(),
    "endowment has 1 entries, expected 2 (one per agent)",
  )
  @test.assert_eq(
    EndowmentNotPerm.to_string(),
    "endowment must give each good to exactly one agent",
  )
}

///|
test "CertificateError Show texts are stable user-facing strings" {
  @test.assert_eq(
    ClaimLength(1, 2).to_string(),
    "certificate claims 1 proposals, expected 2",
  )
  @test.assert_eq(
    PartnerOutOfRange(3, 5).to_string(),
    "proposer 3 claims receiver 5, outside the market",
  )
  @test.assert_eq(
    ReceiverHeldTwice(1).to_string(),
    "receiver 1 is claimed twice",
  )
}

///|
test "CertError Show texts are stable user-facing strings" {
  @test.assert_eq(
    WitnessNotDominating(0, 1).to_string(),
    "witness for (proposer 0, receiver 1) is a lie: 1 prefers 0 to its holder — blocking pair",
  )
  @test.assert_eq(
    HolderMismatch(1, 0, 0, 2).to_string(),
    "witness for (proposer 1, receiver 0) names holder 0, but the matching holds 2",
  )
  @test.assert_eq(
    MissingWitness(1, 0).to_string(),
    "proposer 1 prefers receiver 0 to its partner, but no witness vouches for the refusal",
  )
}
