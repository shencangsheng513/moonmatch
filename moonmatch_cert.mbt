///|
/// Exportable stability certificates.
///
/// `blocking_pairs` already lets anyone RECOMPUTE the verdict; this
/// module lets anyone CHECK a delivered answer without recomputing
/// anything. For every pair (p, r) that proposer p would rather be
/// with than its current partner, the certificate delivers one line
/// of evidence: a witness naming the proposer r actually holds. Each
/// witness is then checked by a single "who appears first in r's
/// list" scan — code so small a third party can audit it by eye.
/// The verification path deliberately shares no rank tables, no
/// queues and no helpers with the mechanisms, which is the whole
/// point of a certificate.
///
/// A certificate is self-contained (it embeds the market and the
/// claimed matching) and round-trips through core/json, so the
/// auditor needs no library data structures, only the blob.

///|
/// One line of evidence: proposer `proposer` courts `receiver`, and
/// `holder` vouches that `receiver` ranks `holder` above `proposer`.
pub struct Witness {
  proposer : Int
  receiver : Int
  holder : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub extend Witness with Eq::{not_equal, equal}

///|
pub extend Witness with @debug.Debug::{to_repr}

///|
pub extend Witness with @json.FromJson::{from_json}

///|
pub extend Witness with ToJson::{to_json}

///|
/// A claimed market + matching + the witness table covering every
/// tempting pair. Values are only meaningful together with `verify`.
pub struct StabilityCert {
  proposer_prefs : Array[Array[Int]]
  receiver_prefs : Array[Array[Int]]
  claim : Array[Int]
  witnesses : Array[Witness]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub extend StabilityCert with Eq::{not_equal, equal}

///|
pub extend StabilityCert with @debug.Debug::{to_repr}

///|
pub extend StabilityCert with @json.FromJson::{from_json}

///|
pub extend StabilityCert with ToJson::{to_json}

///|
/// A certificate that fails to prove what it claims. Each variant
/// names the exact pair at fault, so rejection is actionable, not
/// just a red light.
pub suberror CertError {
  InvalidWitness(Int, Int)
  WitnessNotDominating(Int, Int)
  HolderMismatch(Int, Int, Int, Int)
  MissingWitness(Int, Int)
} derive(Debug)

///|
pub extend CertError with @debug.Debug::{to_repr}

///|
pub impl Show for CertError with fn output(self : CertError, logger) {
  match self {
    InvalidWitness(p, r) =>
      logger.write_string(
        "witness names proposer \{p}, receiver \{r}: outside the market",
      )
    WitnessNotDominating(p, r) =>
      logger.write_string(
        "witness for (proposer \{p}, receiver \{r}) is a lie: \{r} prefers \{p} to its holder — blocking pair",
      )
    HolderMismatch(p, r, claimed, actual) =>
      logger.write_string(
        "witness for (proposer \{p}, receiver \{r}) names holder \{claimed}, but the matching holds \{actual}",
      )
    MissingWitness(p, r) =>
      logger.write_string(
        "proposer \{p} prefers receiver \{r} to its partner, but no witness vouches for the refusal",
      )
  }
}

///|
pub extend CertError with Show::{to_string, output}

///|
/// True when `a` appears before `b` in `row` — the verifier's only
/// ranking primitive, one linear scan, no tables.
fn prefers_before(row : Array[Int], a : Int, b : Int) -> Bool {
  for x in row {
    if x == a {
      return true
    } else if x == b {
      return false
    }
  }
  false
}

///|
/// True when some witness of this proposer already vouches for `r`.
/// Buckets are per-proposer and tiny, which keeps verification cost
/// proportional to the certificate size, not to its square.
fn vouches(bucket : Array[Int], r : Int) -> Bool {
  for x in bucket {
    if x == r {
      return true
    }
  }
  false
}

///|
/// Produce the certificate for this matching: one witness per pair
/// (p, r) that p prefers over its partner, naming r's actual holder.
/// For a stable matching every witness is honest; for an unstable
/// one, the dishonest witness is exactly the blocking pair, and
/// `verify` will say so. A tempting pair whose receiver is unmatched
/// gets no witness -- correctly, since nothing can vouch for it.
pub fn Matching::certificate(self : Matching) -> StabilityCert {
  let n = self.proposer_to_receiver.length()
  let prefs = self.preferences
  let witnesses = Array(capacity=0)
  for p in 0..<n {
    let cur = self.proposer_to_receiver[p]
    let row = prefs.proposer_prefs[p]
    let mut i = 0
    while i < row.length() && row[i] != cur {
      let r = row[i]
      let holder = self.receiver_to_proposer[r]
      if holder >= 0 {
        witnesses.push(Witness::{ proposer: p, receiver: r, holder, })
      }
      i = i + 1
    }
  }
  StabilityCert::{
    proposer_prefs: prefs.proposer_prefs,
    receiver_prefs: prefs.receiver_prefs,
    claim: self.proposer_to_receiver,
    witnesses,
  }
}

///|
/// Check a delivered certificate without recomputing anything.
/// Raises the first defect found (or returns quietly, which IS the
/// verdict: the market is stable under this matching). The only
/// ranking knowledge used is `prefers_before`, shared with nothing
/// in the mechanism files.
pub fn StabilityCert::verify(self : StabilityCert) -> Unit raise {
  // structural errors (ProfileError / CertificateError) propagate
  // undecorated: a certificate that cannot even describe a legal
  // market+matching needs no further checking
  let prefs = Preferences::new(self.proposer_prefs, self.receiver_prefs)
  let m = prefs.matching_from(self.claim)
  // 1. every witness must be in the market and vouch honestly;
  //    while checking, bucket each witness under its proposer so
  //    the coverage scan only consults that proposer's own list
  let n = self.claim.length()
  let m_count = m.receiver_to_proposer.length()
  let buckets = Array(capacity=n)
  while buckets.length() < n {
    buckets.push(Array(capacity=0))
  }
  for w in self.witnesses {
    if w.proposer < 0 || w.proposer >= n {
      raise InvalidWitness(w.proposer, w.receiver)
    } else if w.receiver < 0 || w.receiver >= m_count {
      raise InvalidWitness(w.proposer, w.receiver)
    }
    let actual = m.receiver_to_proposer[w.receiver]
    if w.holder != actual {
      raise HolderMismatch(w.proposer, w.receiver, w.holder, actual)
    }
    if !prefers_before(self.receiver_prefs[w.receiver], w.holder, w.proposer) {
      raise WitnessNotDominating(w.proposer, w.receiver)
    }
    buckets[w.proposer].push(w.receiver)
  }
  // 2. every tempting pair must carry a witness
  for p in 0..<n {
    let cur = self.claim[p]
    let row = self.proposer_prefs[p]
    let mut i = 0
    while i < row.length() && row[i] != cur {
      let r = row[i]
      if !vouches(buckets[p], r) {
        raise MissingWitness(p, r)
      }
      i = i + 1
    }
  }
}

///|
/// Serialize for delivery to a third party.
pub fn StabilityCert::to_json_string(self : StabilityCert) -> String {
  @json.to_json(self).stringify()
}

///|
/// Parse a delivered certificate (raises @json.ParseError or
/// @json.JsonDecodeError on junk input, propagated undecorated).
pub fn StabilityCert::from_json_string(s : String) -> StabilityCert raise {
  let j = @json.parse(s[:])
  @json.from_json(j)
}
