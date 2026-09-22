///|
/// A one-sided exchange (housing) market: `n` agents each start out
/// owning exactly one of `n` indivisible goods. Unlike two-sided
/// matching there is no counterparty consent — ownership itself is the
/// currency — which is why the solution concept changes from "stable"
/// to "in the core", and Top Trading Cycles is the mechanism that
/// implements it (Shapley & Scarf 1974).
pub struct Market {
  prefs : Array[Array[Int]]
  endowment : Array[Int]
} derive(Eq, Debug)

///|
pub extend Market with Eq::{not_equal, equal}

///|
pub extend Market with @debug.Debug::{to_repr}

///|
/// A malformed exchange market.
pub suberror MarketError {
  Empty
  RowNotPerm(Int)
  EndowmentLength(Int, Int)
  EndowmentNotPerm
} derive(Debug)

///|
pub extend MarketError with @debug.Debug::{to_repr}

///|
pub impl Show for MarketError with fn output(self : MarketError, logger) {
  match self {
    Empty => logger.write_string("a housing market needs at least one agent")
    RowNotPerm(agent) =>
      logger.write_string(
        "agent \{agent} preference row must rank every good exactly once",
      )
    EndowmentLength(got, expected) =>
      logger.write_string(
        "endowment has \{got} entries, expected \{expected} (one per agent)",
      )
    EndowmentNotPerm =>
      logger.write_string("endowment must give each good to exactly one agent")
  }
}

///|
pub extend MarketError with Show::{to_string, output}

///|
/// Build an exchange market: every agent must rank all `n` goods
/// (complete strict orders), and the endowment must assign every good
/// to exactly one agent.
///
/// The row check deliberately delegates to the two-sided gate
/// (`check_rows`) and only translates the error: one source of truth
/// for "is this a complete ranking", two honest vocabularies for two
/// kinds of market.
pub fn Market::new(
  prefs : Array[Array[Int]],
  endowment : Array[Int],
) -> Market raise MarketError {
  let n = prefs.length()
  if n == 0 {
    raise Empty
  }
  check_rows(prefs, n, Proposer) catch {
    ProfileError::Empty => raise MarketError::Empty
    RowLength(_, i, _, _) => raise RowNotPerm(i)
    NotPermutation(_, i) => raise RowNotPerm(i)
  }
  if endowment.length() != n {
    raise EndowmentLength(endowment.length(), n)
  }
  check_rows([endowment], n, Receiver) catch {
    ProfileError::Empty => raise EndowmentNotPerm
    RowLength(_, _, _, _) => raise EndowmentNotPerm
    NotPermutation(_, _) => raise EndowmentNotPerm
  }
  Market::{ prefs, endowment, }
}

///|
/// Top Trading Cycles: each waiting agent points at its favourite good
/// still in the market; every ownership-pointer cycle trades at once
/// and its members leave. At least one cycle exists per round (the
/// pointing graph is a function on the waiting set), so this terminates
/// in at most `n` rounds, and the outcome is in the core — verifiable
/// below rather than taken on trust.
pub fn Market::top_trading_cycles(self : Market) -> Array[Int] {
  let n = self.prefs.length()
  let alloc = filled(n, -1)
  let owner_of = filled(n, 0)
  for a in 0..<n {
    owner_of[self.endowment[a]] = a
  }
  let cursor = filled(n, 0)
  let mut remaining = n
  while remaining > 0 {
    // round setup: each waiting agent points to its best in-market
    // good; a good is in market while its owner still waits
    let pointed_good = filled(n, -1)
    let points_to = filled(n, -1)
    for a in 0..<n {
      if alloc[a] == -1 {
        let row = self.prefs[a]
        let mut k = cursor[a]
        while alloc[owner_of[row[k]]] != -1 {
          k = k + 1
        }
        cursor[a] = k
        pointed_good[a] = row[k]
        points_to[a] = owner_of[row[k]]
      }
    }
    // walk pointer chains until one closes a cycle
    let state = filled(n, 0)
    let path = Array(capacity=remaining)
    let mut cycle_head = -1
    let mut start = 0
    while start < n {
      if alloc[start] == -1 && state[start] == 0 {
        path.clear()
        let mut cur = start
        while state[cur] == 0 {
          state[cur] = 1
          path.push(cur)
          cur = points_to[cur]
        }
        if state[cur] == 1 {
          cycle_head = cur
          break
        }
        for x in path {
          state[x] = 2
        }
      }
      start = start + 1
    }
    // execute the cycle: every member keeps the good it pointed at
    let mut i = 0
    while cycle_head != -1 && i < path.length() {
      if path[i] == cycle_head {
        break
      }
      i = i + 1
    }
    if cycle_head != -1 {
      while i < path.length() {
        let a = path[i]
        alloc[a] = pointed_good[a]
        remaining = remaining - 1
        i = i + 1
      }
    }
  }
  alloc
}

///|
/// Individual rationality: no agent finishes with a good ranked below
/// the one it brought in. A theorem about TTC — asserted here as an
/// audit that runs different code from the mechanism.
pub fn Market::is_individually_rational(
  self : Market,
  alloc : Array[Int],
) -> Bool {
  let ranks = ranks_of(self.prefs)
  let n = self.prefs.length()
  let mut ok = true
  for a in 0..<n {
    if alloc[a] == -1 || ranks[a][alloc[a]] > ranks[a][self.endowment[a]] {
      ok = false
    }
  }
  ok
}

///|
/// Exhaustive Pareto audit: every allocation that makes at least one
/// agent strictly better off and no agent worse off. Enumerates all
/// n! assignments — exponential on purpose: it is the dumb-but-trust-
/// me reference the quickcheck properties compare TTC against, and is
/// only sane for tiny markets (n <= 6).
pub fn Market::pareto_dominators(
  self : Market,
  alloc : Array[Int],
) -> Array[Array[Int]] {
  let n = self.prefs.length()
  let ranks = ranks_of(self.prefs)
  let out = Array(capacity=0)
  for cand in all_perms(n) {
    let mut weak_all = true
    let mut strict_any = false
    for a in 0..<n {
      if ranks[a][cand[a]] > ranks[a][alloc[a]] {
        weak_all = false
      } else if ranks[a][cand[a]] < ranks[a][alloc[a]] {
        strict_any = true
      }
    }
    if weak_all && strict_any {
      out.push(cand)
    }
  }
  out
}

///|
fn all_perms(n : Int) -> Array[Array[Int]] {
  if n == 0 {
    [[]]
  } else {
    let out = Array(capacity=0)
    for sub in all_perms(n - 1) {
      for i = 0; i <= sub.length(); i = i + 1 {
        let p = Array(capacity=n)
        for j in 0..<n {
          if j < i {
            p.push(sub[j])
          } else if j == i {
            p.push(n - 1)
          } else {
            p.push(sub[j - 1])
          }
        }
        out.push(p)
      }
    }
    out
  }
}
