///|
/// Which side of the market a preference row belongs to.
pub(all) enum Side {
  Proposer
  Receiver
} derive(Eq, Debug)

///|
pub extend Side with Eq::{not_equal, equal}

///|
pub extend Side with @debug.Debug::{to_repr}

///|
fn side_label(side : Side) -> String {
  match side {
    Proposer => "proposer"
    Receiver => "receiver"
  }
}

///|
/// A malformed market description. Every `Preferences` value is built
/// through `Preferences::new`, the single invariant gate; no downstream
/// algorithm re-checks these conditions.
pub suberror ProfileError {
  Empty
  RowLength(Side, Int, Int, Int)
  NotPermutation(Side, Int)
} derive(Debug)

///|
pub extend ProfileError with @debug.Debug::{to_repr}

///|
pub impl Show for ProfileError with fn output(self : ProfileError, logger) {
  match self {
    Empty =>
      logger.write_string(
        "a market needs at least one proposer and one receiver",
      )
    RowLength(side, row, expected, got) =>
      logger.write_string(
        "\{side_label(side)} preference row \{row} has \{got} entries, expected \{expected}",
      )
    NotPermutation(side, row) =>
      logger.write_string(
        "\{side_label(side)} preference row \{row} must rank every counterparty exactly once",
      )
  }
}

///|
pub extend ProfileError with Show::{to_string, output}

///|
/// A two-sided strict-preference market: `n` proposers, `m` receivers,
/// agents identified by their row index (0-based).
///
/// Row `i` of `proposer_prefs` ranks every receiver best-to-worst; row
/// `i` of `receiver_prefs` ranks every proposer best-to-worst. Complete
/// lists are mandatory because the theorems behind these algorithms
/// (stability always exists; deferred acceptance returns the
/// proposer-optimal stable matching) are stated for complete profiles —
/// silently tolerating a gap would change the theorem being implemented.
pub struct Preferences {
  proposer_prefs : Array[Array[Int]]
  receiver_prefs : Array[Array[Int]]
} derive(Eq, Debug)

///|
pub extend Preferences with Eq::{not_equal, equal}

///|
pub extend Preferences with @debug.Debug::{to_repr}

///|
fn check_rows(
  rows : Array[Array[Int]],
  width : Int,
  side : Side,
) -> Unit raise ProfileError {
  let n = rows.length()
  for i = 0; i < n; i = i + 1 {
    let row = rows[i]
    if row.length() != width {
      raise RowLength(side, i, width, row.length())
    }
    let seen = Array(capacity=width)
    while seen.length() < width {
      seen.push(false)
    }
    for x in row {
      if x < 0 || x >= width || seen[x] {
        raise NotPermutation(side, i)
      }
      seen[x] = true
    }
  }
}

///|
/// Build a market from raw ranking tables, rejecting empty markets,
/// ragged rows, and rows that are not complete permutations of the other
/// side's indices.
pub fn Preferences::new(
  proposer_prefs : Array[Array[Int]],
  receiver_prefs : Array[Array[Int]],
) -> Preferences raise ProfileError {
  let n = proposer_prefs.length()
  let m = receiver_prefs.length()
  if n == 0 || m == 0 {
    raise Empty
  }
  check_rows(proposer_prefs, m, Proposer)
  check_rows(receiver_prefs, n, Receiver)
  Preferences::{ proposer_prefs, receiver_prefs, }
}

///|
/// `out[i][x]` = the position of `x` in agent `i`'s ranking (0 = best).
/// Rank lookups are the hot inner loop of every mechanism and every
/// audit, so rankings are turned into position tables once.
fn ranks_of(rows : Array[Array[Int]]) -> Array[Array[Int]] {
  let out = Array(capacity=rows.length())
  for row in rows {
    let r = Array(capacity=row.length())
    while r.length() < row.length() {
      r.push(0)
    }
    let w = row.length()
    for k = 0; k < w; k = k + 1 {
      r[row[k]] = k
    }
    out.push(r)
  }
  out
}

///|
fn filled(n : Int, v : Int) -> Array[Int] {
  let a = Array(capacity=n)
  while a.length() < n {
    a.push(v)
  }
  a
}

///|
/// The outcome of running a mechanism on a `Preferences`: for each agent
/// on each side, whom they are matched to, or `-1` when unmatched.
pub struct Matching {
  preferences : Preferences
  proposer_to_receiver : Array[Int]
  receiver_to_proposer : Array[Int]
} derive(Eq, Debug)

///|
pub extend Matching with Eq::{not_equal, equal}

///|
pub extend Matching with @debug.Debug::{to_repr}

///|
/// A claimed proposer->receiver table contradicts the market: wrong
/// length, an out-of-range partner, or a receiver claimed twice.
pub suberror CertificateError {
  ClaimLength(Int, Int)
  PartnerOutOfRange(Int, Int)
  ReceiverHeldTwice(Int)
} derive(Debug)

///|
pub extend CertificateError with @debug.Debug::{to_repr}

///|
pub impl Show for CertificateError with fn output(
  self : CertificateError,
  logger,
) {
  match self {
    ClaimLength(got, expected) =>
      logger.write_string(
        "certificate claims \{got} proposals, expected \{expected}",
      )
    PartnerOutOfRange(p, r) =>
      logger.write_string(
        "proposer \{p} claims receiver \{r}, outside the market",
      )
    ReceiverHeldTwice(r) =>
      logger.write_string("receiver \{r} is claimed twice")
  }
}

///|
pub extend CertificateError with Show::{to_string, output}

///|
/// Rebuild a Matching from a claimed proposer->receiver table so any
/// outsider — auditor, CLI, test — can run `is_stable` on a
/// certificate it was handed rather than on one the library just
/// produced. `Matching` values are deliberately read-only outside
/// this package; this validating door is how they are made. -1 means
/// unmatched.
pub fn Preferences::matching_from(
  self : Preferences,
  proposer_to_receiver : Array[Int],
) -> Matching raise CertificateError {
  let n = self.proposer_prefs.length()
  let m = self.receiver_prefs.length()
  if proposer_to_receiver.length() != n {
    raise ClaimLength(proposer_to_receiver.length(), n)
  }
  let r2p = filled(m, -1)
  for p in 0..<n {
    let r = proposer_to_receiver[p]
    if r >= 0 {
      if r >= m {
        raise PartnerOutOfRange(p, r)
      }
      if r2p[r] != -1 {
        raise ReceiverHeldTwice(r)
      }
      r2p[r] = p
    } else if r != -1 {
      raise PartnerOutOfRange(p, r)
    }
  }
  Matching::{
    preferences: self,
    proposer_to_receiver,
    receiver_to_proposer: r2p,
  }
}

///|
/// Gale-Shapley deferred acceptance: every unmatched proposer keeps
/// proposing down its list; receivers hold the best offer so far and
/// reject the rest. At most `n * m` proposals, so it terminates fast,
/// and the result is stable — independently verifiable below with
/// `Matching::blocking_pairs` rather than taken on trust.
pub fn Preferences::deferred_acceptance(self : Preferences) -> Matching {
  let n = self.proposer_prefs.length()
  let m = self.receiver_prefs.length()
  let r_ranks = ranks_of(self.receiver_prefs)
  let p_to_r = filled(n, -1)
  let r_to_p = filled(m, -1)
  let next = filled(n, 0)
  let queue = Array(capacity=n)
  for i in 0..<n {
    queue.push(i)
  }
  let mut head = 0
  while head < queue.length() {
    let p = queue[head]
    head = head + 1
    let row = self.proposer_prefs[p]
    let k = next[p]
    // k >= row.length() means p's list is exhausted (possible only when
    // there are more proposers than receivers); p stays unmatched.
    if k < row.length() {
      next[p] = k + 1
      let r = row[k]
      let holder = r_to_p[r]
      if holder == -1 {
        r_to_p[r] = p
        p_to_r[p] = r
      } else if r_ranks[r][p] < r_ranks[r][holder] {
        r_to_p[r] = p
        p_to_r[p] = r
        p_to_r[holder] = -1
        queue.push(holder)
      } else {
        queue.push(p)
      }
    }
  }
  Matching::{
    preferences: self,
    proposer_to_receiver: p_to_r,
    receiver_to_proposer: r_to_p,
  }
}

///|
/// Brute-force blocking-pair scan: every (proposer, receiver) pair that
/// would rather leave this matching for each other. A matching is stable
/// iff the result is empty.
///
/// This deliberately does not reuse anything from the mechanism that
/// produced the matching: the certificate is only worth having if it is
/// computed independently (O(n * m) rank-table scans).
pub fn Matching::blocking_pairs(self : Matching) -> Array[(Int, Int)] {
  let p_ranks = ranks_of(self.preferences.proposer_prefs)
  let r_ranks = ranks_of(self.preferences.receiver_prefs)
  let n = self.proposer_to_receiver.length()
  let m = self.receiver_to_proposer.length()
  let out = Array(capacity=0)
  for p in 0..<n {
    let cur = self.proposer_to_receiver[p]
    let prow = p_ranks[p]
    for r in 0..<m {
      let p_prefers = cur == -1 || prow[r] < prow[cur]
      if p_prefers {
        let holder = self.receiver_to_proposer[r]
        let r_prefers = holder == -1 || r_ranks[r][p] < r_ranks[r][holder]
        if r_prefers {
          out.push((p, r))
        }
      }
    }
  }
  out
}

///|
/// True when no blocking pair exists — the defining property of a stable
/// matching (Shapley & Flood 1962; Roth 1985 for the general case).
pub fn Matching::is_stable(self : Matching) -> Bool {
  self.blocking_pairs().length() == 0
}
