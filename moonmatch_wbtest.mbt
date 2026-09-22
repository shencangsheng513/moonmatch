///|
/// Whitebox: error constructors are read-only outside the package
/// (`pub suberror` only opens matching), so pinning Show wording
/// has to happen inside it.
test "ProfileError Show texts are stable user-facing strings" {
  // Error messages are CLI output; pin the full wording so renames break
  // tests (this core has no String::contains, so equality is the check).
  @test.assert_eq(
    Empty.to_string(),
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
