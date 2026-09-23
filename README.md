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
says the algorithm you choose changes who wins. The registry already has
naive DA/TTC implementations (see the landscape table below — checking for
them honestly is what shaped this library). What none of them provide is
the part this library is built around: every outcome ships with an
**independently auditable stability certificate** — a brute-force
blocking-pair scan, and an exportable witness blob a stranger can verify
without trusting or re-running any code here.

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
- [x] benchmarks: fixed-seed markets through `moonbitlang/core/bench`,
      measured numbers (and one measured-then-fixed hotspot) below

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

## Performance, measured (not promised)

`moon run --release benchmarks` measures every hot path on square
random markets from a fixed-seed LCG — same inputs, same numbers, every
run — using the official `moonbitlang/core/bench` harness (its
batching and winsorised statistics, not our stopwatch). Medians of 10
runs on the author's laptop, microseconds:

| n | `deferred_acceptance` | `blocking_pairs` scan | `certificate` | `verify` | `top_trading_cycles` |
| --- | --- | --- | --- | --- | --- |
| 100 | 43 | 94 | 11 | 118 | 33 |
| 300 | 332 | 773 | 38 | 775 | 176 |
| 1000 | 3,439 | 12,548 | 224 | 8,618 | 1,184 |

Two honest footnotes. First: the audits (`blocking_pairs`, `verify`)
are Θ(n·m) *by design* — they re-check everything independently of the
mechanisms, and that duplication is exactly what makes the certificate
worth something. Second: this table caught a real bug in itself — the
first version of `verify` was quadratic in certificate size (23.8 ms at
n=1000, 100× the cost of generating the same certificate); it now
buckets witnesses during the honesty pass (8.6 ms), and the remaining
gap is the deliberate independent scanning.

## Where this sits in the Mooncakes registry

Keyword sweeps are cheap to get wrong, so every neighbour below was
verified at README/interface level, twice. (An earlier version of this
table described `moonbit-auction` as "one-sided bidding only" — a deeper
look found a whole `src/matching` subtree, and the correction is part of
this project's story.) As of 2026-09-23:

| Neighbour | What it actually has | What it does not have |
| --- | --- | --- |
| `pk9993/moonbit-auction/src/matching` | DA, TTC, TTC-with-chains, capacitated matching; `audit_matching` counts duplicate proposers, invalid references, capacity overflow | any *stability* check — the repo has no blocking-pair logic at all; no exportable certificate |
| `bobzhang/loop_invariants_graph/gale_shapley_stable_matching` (2026-09-22) | square-table DA + `is_stable -> Bool`, with loop-invariant documentation | one-to-one only (no HR quotas, no TTC); the check is in-library trust, not an artifact a third party can audit |
| `hutingyu-nuist/moonballot` | IRV vote tabulation | two-sided matching of any kind |
| `SUIKKKA/shiftweave` | shift-scheduling constraint rules | game-theoretic stability |

The gap MoonMatch occupies is the column on the right: **stability as a
verifiable artifact** — exportable witness certificates, an outsider-only
verification path, capacity-aware HR certificates, and TTC IR/Pareto
audits, none of which any registry package provides.

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
