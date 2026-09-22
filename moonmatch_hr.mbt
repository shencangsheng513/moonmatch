///|
/// Per-hospital capacity problems for the hospital/residents mechanism.
/// Kept separate from `ProfileError` because quotas are a second gate:
/// the `Preferences` themselves stay legal, only the capacity table can
/// contradict the market shape.
pub suberror QuotaError {
  QuotaLength(Int, Int)
  NonPositiveQuota(Int, Int)
} derive(Debug)

///|
pub extend QuotaError with @debug.Debug::{to_repr}

///|
pub impl Show for QuotaError with fn output(self : QuotaError, logger) {
  match self {
    QuotaLength(got, expected) =>
      logger.write_string("got \{got} quotas for \{expected} hospitals")
    NonPositiveQuota(hospital, quota) =>
      logger.write_string(
        "hospital \{hospital} has quota \{quota}, quotas must be positive",
      )
  }
}

///|
pub extend QuotaError with Show::{to_string, output}

///|
/// The outcome of a hospital/residents run: residents see one hospital
/// (or -1), hospitals see a list of residents up to their quota.
pub struct HRAssignment {
  preferences : Preferences
  quotas : Array[Int]
  proposer_to_receiver : Array[Int]
  receiver_holders : Array[Array[Int]]
} derive(Eq, Debug)

///|
pub extend HRAssignment with Eq::{not_equal, equal}

///|
pub extend HRAssignment with @debug.Debug::{to_repr}

///|
fn worst_holder(holders : Array[Int], ranks : Array[Int]) -> Int {
  let mut w = holders[0]
  for x in holders {
    if ranks[x] > ranks[w] {
      w = x
    }
  }
  w
}

///|
/// Remove `elem` (which must be present) from `holders`. MoonBit's
/// `Array::remove` takes an index, so the position is found first.
fn evict(holders : Array[Int], elem : Int) -> Unit {
  let mut i = 0
  while holders[i] != elem {
    i = i + 1
  }
  ignore(holders.remove(i))
}

///|
/// True when hospital `r` would rather hold proposer `p` than its
/// current situation: a free seat, or a ranking above its worst holder.
fn hospital_prefers(
  holders : Array[Int],
  ranks : Array[Int],
  p : Int,
  quota : Int,
) -> Bool {
  if holders.length() < quota {
    true
  } else {
    ranks[p] < ranks[worst_holder(holders, ranks)]
  }
}

///|
/// Deferred acceptance with many-to-one receivers (Roth & Sotomayor
/// 1990, the algorithm behind US resident matching): identical to
/// `deferred_acceptance` when every quota is 1; otherwise a hospital
/// holds its best `quota` offers instead of just one.
pub fn Preferences::hospital_residents(
  self : Preferences,
  quotas : Array[Int],
) -> HRAssignment raise QuotaError {
  let n = self.proposer_prefs.length()
  let m = self.receiver_prefs.length()
  if quotas.length() != m {
    raise QuotaLength(quotas.length(), m)
  }
  for j in 0..<m {
    if quotas[j] < 1 {
      raise NonPositiveQuota(j, quotas[j])
    }
  }
  let r_ranks = ranks_of(self.receiver_prefs)
  let p_to_r = filled(n, -1)
  let next = filled(n, 0)
  let holders = Array(capacity=m)
  for j in 0..<m {
    holders.push(Array(capacity=quotas[j]))
  }
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
    // like the one-to-one DA, an exhausted list can only happen when
    // capacity is scarce; that resident simply stays unmatched
    if k < row.length() {
      next[p] = k + 1
      let r = row[k]
      let h = holders[r]
      if h.length() < quotas[r] {
        h.push(p)
        p_to_r[p] = r
      } else {
        let worst = worst_holder(h, r_ranks[r])
        if r_ranks[r][p] < r_ranks[r][worst] {
          evict(h, worst)
          h.push(p)
          p_to_r[p] = r
          p_to_r[worst] = -1
          queue.push(worst)
        } else {
          queue.push(p)
        }
      }
    }
  }
  HRAssignment::{
    preferences: self,
    quotas,
    proposer_to_receiver: p_to_r,
    receiver_holders: holders,
  }
}

///|
/// Blocking pairs under capacity: a resident prefers some hospital to
/// their current post (or to being unmatched), and that hospital either
/// has a free seat or ranks the resident above its current worst
/// holder. An empty result means the assignment is stable; like the
/// one-to-one certificate this scan shares no logic with the mechanism.
pub fn HRAssignment::blocking_pairs(self : HRAssignment) -> Array[(Int, Int)] {
  let p_ranks = ranks_of(self.preferences.proposer_prefs)
  let r_ranks = ranks_of(self.preferences.receiver_prefs)
  let n = self.proposer_to_receiver.length()
  let m = self.receiver_holders.length()
  let out = Array(capacity=0)
  for p in 0..<n {
    let cur = self.proposer_to_receiver[p]
    let prow = p_ranks[p]
    for r in 0..<m {
      let p_prefers = cur == -1 || prow[r] < prow[cur]
      if p_prefers {
        let held = hospital_prefers(
          self.receiver_holders[r],
          r_ranks[r],
          p,
          self.quotas[r],
        )
        if held {
          out.push((p, r))
        }
      }
    }
  }
  out
}

///|
pub fn HRAssignment::is_stable(self : HRAssignment) -> Bool {
  self.blocking_pairs().length() == 0
}
