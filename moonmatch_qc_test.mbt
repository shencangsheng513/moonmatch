///|
/// Property-based tests (core quickcheck, deterministic seed).
/// `perm_from` turns arbitrary ints into legal complete rankings by
/// drawing from a shrinking pool of free slots, so every property
/// below is a claim about ALL markets of the drawn shape, not about
/// the handful of hand-picked examples the unit tests cover.
fn perm_from(seed : Array[Int], n : Int, salt : Int) -> Array[Int] {
  let out = Array(capacity=n)
  let free = Array(capacity=n)
  for i in 0..<n {
    free.push(i)
  }
  let len = seed.length()
  for i in 0..<n {
    // draw k from the shrinking free pool; free.remove(k) is index-based.
    // `& 0xffff` instead of abs: quickcheck draws ints near the 64-bit
    // boundary, where abs can overflow back into the negatives.
    let k = if len == 0 {
      0
    } else {
      ((seed[(i * 7 + 3 + salt) % len] & 0xffff) + salt) % free.length()
    }
    out.push(free[k])
    ignore(free.remove(k))
  }
  out
}

///|
fn qc_prefs(
  seed : Array[Int],
  n : Int,
  m : Int,
) -> @moonmatch.Preferences raise {
  let ps = Array(capacity=n)
  for i in 0..<n {
    ps.push(perm_from(seed, m, i))
  }
  let rs = Array(capacity=m)
  for j in 0..<m {
    rs.push(perm_from(seed, n, 100 + j))
  }
  // The invariant gate must never reject a generated input; if it
  // does, the generator (not the API) is broken.
  @moonmatch.Preferences::new(ps, rs) catch {
    e => fail("generated input should pass the gate: \{e}")
  }
}

///|
/// Preference rank of partner `j` in `row`; being unmatched is each
/// proposer's worst option (completeness of the market is what the
/// ProfileError gate guarantees).
fn rank_of(row : Array[Int], j : Int) -> Int {
  if j < 0 {
    row.length()
  } else {
    let mut r = 0
    while row[r] != j {
      r = r + 1
    }
    r
  }
}

///|
fn all_ints(n : Int, v : Int) -> Array[Int] {
  let a = Array(capacity=n)
  for _ in 0..<n {
    a.push(v)
  }
  a
}

///|
fn all_bools(n : Int, v : Bool) -> Array[Bool] {
  let a = Array(capacity=n)
  for _ in 0..<n {
    a.push(v)
  }
  a
}

///|
test "quickcheck: DA output is a consistent matching and never leaves a blocking pair" {
  @quickcheck.check((input : (Int, Int, Array[Int])) => {
    let (a, b, seed) = input
    let n = (a % 5 + 5) % 5 + 1
    let m = (b % 5 + 5) % 5 + 1
    let matching = qc_prefs(seed, n, m).deferred_acceptance()
    if matching.proposer_to_receiver.length() != n ||
      matching.receiver_to_proposer.length() != m {
      return false
    }
    let taken = all_bools(m, false)
    for p in 0..<n {
      let r = matching.proposer_to_receiver[p]
      if r >= 0 {
        if taken[r] || matching.receiver_to_proposer[r] != p {
          return false
        }
        taken[r] = true
      }
    }
    for r in 0..<m {
      let p = matching.receiver_to_proposer[r]
      if p != -1 && matching.proposer_to_receiver[p] != r {
        return false
      }
    }
    matching.is_stable()
  })
}

///|
test "quickcheck: hospital_residents with all-ones quotas matches DA on every market" {
  @quickcheck.check((input : (Int, Int, Array[Int])) => {
    let (a, b, seed) = input
    let n = (a % 5 + 5) % 5 + 1
    let m = (b % 5 + 5) % 5 + 1
    let prefs = qc_prefs(seed, n, m)
    let hr = prefs.hospital_residents(all_ints(m, 1)) catch {
      e => fail("all-ones quotas must be accepted: \{e}")
    }
    @test.assert_eq(
      hr.proposer_to_receiver,
      prefs.deferred_acceptance().proposer_to_receiver,
    )
    @test.assert_eq(hr.blocking_pairs().length(), 0)
    // each hospital holds at most its one seat, consistent p2p <-> holders
    for r in 0..<m {
      if hr.receiver_holders[r].length() > 1 {
        return false
      }
      for p in 0..<hr.receiver_holders[r].length() {
        if hr.proposer_to_receiver[hr.receiver_holders[r][p]] != r {
          return false
        }
      }
    }
    true
  })
}

///|
/// The classic theorem, checked rather than cited: among ALL stable
/// matchings (enumerated exhaustively for tiny square markets), the
/// DA outcome is at least as good for every proposer.
test "quickcheck: DA is proposer-optimal among all stable matchings (n <= 4)" {
  @quickcheck.check((input : (Int, Array[Int])) => {
    let (a, seed) = input
    let n = (a % 4 + 4) % 4 + 1
    let prefs = qc_prefs(seed, n, n)
    let da = prefs.deferred_acceptance()
    let mut base = 1
    for _ in 0..<n {
      base = base * (n + 1)
    }
    for code in 0..<base {
      // decode base-(n+1): slot value v - 1 is the partner, -1 unmatched
      let mut c = code
      let p2p = Array(capacity=n)
      for _ in 0..<n {
        p2p.push(c % (n + 1) - 1)
        c = c / (n + 1)
      }
      let r2p = all_ints(n, -1)
      let mut valid = true
      for p in 0..<n {
        let r = p2p[p]
        if r >= 0 {
          if r2p[r] != -1 {
            valid = false
          } else {
            r2p[r] = p
          }
        }
      }
      if valid {
        let candidate = prefs.matching_from(p2p) catch {
          e => fail("generator built an invalid claim: \{e}")
        }
        if candidate.is_stable() {
          for p in 0..<n {
            let da_rank = rank_of(
              prefs.proposer_prefs[p],
              da.proposer_to_receiver[p],
            )
            let alt_rank = rank_of(prefs.proposer_prefs[p], p2p[p])
            if alt_rank < da_rank {
              return false
            }
          }
        }
      }
    }
    true
  })
}

///|
test "quickcheck: TTC output is a permutation, individually rational and core (n <= 5)" {
  @quickcheck.check((input : (Int, Array[Int])) => {
    let (a, seed) = input
    let n = (a % 5 + 5) % 5 + 1
    let rows = Array(capacity=n)
    for i in 0..<n {
      rows.push(perm_from(seed, n, i))
    }
    let market = @moonmatch.Market::new(rows, perm_from(seed, n, 200)) catch {
      e => fail("generated market should pass the gate: \{e}")
    }
    let alloc = market.top_trading_cycles()
    if alloc.length() != n {
      return false
    }
    let seen = all_bools(n, false)
    for p in 0..<n {
      let g = alloc[p]
      if g < 0 || g >= n || seen[g] {
        return false
      }
      seen[g] = true
    }
    if !market.is_individually_rational(alloc) {
      return false
    }
    market.pareto_dominators(alloc).length() == 0
  })
}

///|
/// The witness certificate and the brute-force scan share no code, so
/// their agreement on RANDOM (mostly unstable) matchings is a real
/// cross-check, not a tautology: verify passes exactly when the
/// independent scan finds no blocking pair, and the JSON round trip
/// changes nothing.
test "quickcheck: certificate verify agrees with the brute-force scan (n, m <= 4)" {
  @quickcheck.check((input : (Int, Int, Array[Int])) => {
    let (a, b, seed) = input
    let n = (a % 4 + 4) % 4 + 1
    let m = (b % 4 + 4) % 4 + 1
    let prefs = qc_prefs(seed, n, m)
    // arbitrary (usually unstable) matching: the first k proposers take
    // a shuffled set of receivers, the rest go unmatched
    let k = if n < m { n } else { m }
    let order = perm_from(seed, m, 300)
    let p2p = Array(capacity=n)
    for p in 0..<n {
      p2p.push(if p < k { order[p] } else { -1 })
    }
    let arbitrary = prefs.matching_from(p2p) catch {
      e => fail("generator built an invalid claim: \{e}")
    }
    let cert = arbitrary.certificate()
    let back = @moonmatch.StabilityCert::from_json_string(cert.to_json_string()) catch {
      e => fail("certificate round-trip failed: \{e}")
    }
    if back != cert {
      return false
    }
    let mut verified = true
    back.verify() catch {
      _ => verified = false
    }
    verified == (arbitrary.blocking_pairs().length() == 0)
  })
}
