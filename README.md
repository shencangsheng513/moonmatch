# MoonMatch

[![CI](https://github.com/shencangsheng513/moonmatch/actions/workflows/ci.yml/badge.svg)](https://github.com/shencangsheng513/moonmatch/actions/workflows/ci.yml)

Matching-market engine for [MoonBit](https://www.moonbitlang.com): Gale-Shapley
stable matching, hospital/residents with quotas, and top trading cycles —
every outcome ships with a **machine-checkable stability certificate**, so
"this allocation is stable" is a verified fact, not a claim.

> 🚧 WIP — 2026 MoonBit Hackathon (September edition) entry, developed in the
> open.

## Why

Roommate pairing, school-seat assignment, shift swaps, organ exchanges:
these are all *matching markets*, and the 2012 Nobel Prize (Roth & Shapley)
says the algorithm you choose changes who wins. The MoonBit ecosystem has
auctions, voting tabulation, and scheduling rule engines — but no matching
engine at all. This library fills that gap with an emphasis the reference
implementations don't have: every matching can be *audited* by an
independent brute-force blocking-pair scan.

## Status

- [x] `Preferences`: complete strict rankings enforced at construction
- [x] `deferred_acceptance` (Gale-Shapley) + independent stability certificate
- [x] `matching_from`: rebuild a `Matching` from a *claimed* table and audit it
- [x] hospital/residents (many-to-one DA with quotas) + capacity-aware certificate
- [x] top trading cycles (Shapley-Scarf) + individual-rationality and Pareto audits
- [x] CLI: `da` / `hr` / `ttc` / `check` / `cert` / `verify`, verdict printed
      as a `certificate:` line
- [x] property-based tests: stability, quota-1 equivalence, proposer-optimality
      against exhaustive stable-set enumeration, TTC core membership,
      certificate ⟺ brute-force scan agreement
- [x] exportable witness certificates: the JSON blob alone carries every
      fact needed — an auditor can even re-implement `verify` from scratch
      in ~40 trivial lines and check the answer without trusting this code

## The CLI, in one honest demo

`check` runs **no** algorithm — it takes somebody else's answer and audits it:

```
$ moon run cli -- check "1,0,2|0,1,2|0,1,2" "2,1,0|0,2,1|0,1,2" "0,1,2"
P0 -> R0
P1 -> R1
P2 -> R2
certificate: UNSTABLE, 4 blocking pair(s): (P0, R1) (P1, R0) (P2, R0) (P2, R1)
```

## Certificates you can hand to a stranger

`cert` exports the DA answer together with one *witness* per tempting pair
("P1 courted R0; R0 really holds P2, who it ranks above P1"). `verify`
then checks a delivered blob **without running any matching algorithm**:
each witness is one "who appears first in this list" scan, and the
verification path shares no rank tables, queues or helpers with the
mechanisms — so accepting a certificate is not the same as trusting us.

```
$ moon run cli -- cert "1,0,2|0,1,2|0,1,2" "2,1,0|0,2,1|0,1,2"
certificate: {"proposer_prefs":[[1,0,2],[0,1,2],[0,1,2]],"receiver_prefs":[[2,1,0],[0,2,1],[0,1,2]],"claim":[1,2,0],"witnesses":[{"proposer":1,"receiver":0,"holder":2},{"proposer":1,"receiver":1,"holder":0}]}

$ moon run cli -- verify '{"proposer_prefs":...,"witnesses":[]}'
verify: REJECTED: proposer 1 prefers receiver 0 to its partner, but no witness vouches for the refusal
```

If a witness lies about the market's true holder, the rejection names the
exact blocking pair it was hiding (`witness for (proposer 0, receiver 1)
is a lie: ...`). A quickcheck property verifies on random markets that
`verify` and the independent brute-force scan *always* agree.

## Where this sits in the Mooncakes registry

Searched 77 keywords (3 rounds, README-level verification) before picking
the topic. Adjacent packages exist; none does two-sided matching with
auditable certificates:

| Neighbour | What it does | Why MoonMatch is not it |
| --- | --- | --- |
| `pk9993/moonbit-auction` | price-based auctions | one-sided bidding, no preferences-over-partners stability |
| `hutingyu-nuist/moonballot` | IRV vote tabulation | tallies votes, produces no two-sided matching |
| `SUIKKKA/shiftweave` | shift-scheduling rules | constraint rules, not game-theoretic stability |
| georust/geo port, CRDT×4, bloom×4, FFT, HLL… | other saturated niches | `gale`, `stable_marriage`, `two_sided`, `roommate`, `matching-markets` return **zero hits** |

## Quick example

```moonbit
// proposers and receivers are row indices; each row ranks the other
// side best-to-worst and must be a complete permutation
let market = Preferences::new(
  [[0, 1], [1, 0]], // proposers' rankings
  [[0, 1], [0, 1]], // receivers' rankings
)
let m = market.deferred_acceptance()
m.is_stable() // true — verified by a blocking-pair scan, not trusted
```

## License

Apache-2.0
