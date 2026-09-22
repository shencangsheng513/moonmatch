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
- [ ] `deferred_acceptance` (Gale-Shapley) + stability certificate
- [ ] hospital/residents (quotas), top trading cycles
- [ ] CLI and property-based audit against brute force

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
