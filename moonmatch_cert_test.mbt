///|
/// Blackbox audit tests: every certificate below is either produced
/// by the public `certificate()` method or hand-written as a JSON
/// blob — the same two doors a third-party auditor has. Nothing here
/// can reach into the package.

///|
/// Blob assembly mirrors the exact wire format the library emits;
/// keeping it literal (escaped quotes, like core/json's own tests)
/// is what makes these tests outsider-authored.
fn w(p : Int, r : Int, h : Int) -> String {
  "{\"proposer\":\{p},\"receiver\":\{r},\"holder\":\{h}}"
}

///|
fn blob(claim : String, ws : String) -> String {
  "{\"proposer_prefs\":[[1,0,2],[0,1,2],[0,1,2]],\"receiver_prefs\":[[2,1,0],[0,2,1],[0,1,2]],\"claim\":\{claim},\"witnesses\":\{ws}}"
}

///|
let market_json : String = blob(
  "[1,2,0]",
  "[" + w(1, 0, 2) + "," + w(1, 1, 0) + "]",
)

///|
fn fixture() -> @moonmatch.Preferences raise {
  market([[1, 0, 2], [0, 1, 2], [0, 1, 2]], [[2, 1, 0], [0, 2, 1], [0, 1, 2]])
}

///|
test "the certificate of the hand-traced DA says exactly what the paper trace says" {
  let cert = fixture().deferred_acceptance().certificate()
  @test.assert_eq(cert.claim, [1, 2, 0])
  // Only P1 is tempted: it prefers R0 (held by P2) and R1 (held by P0)
  // to its partner R2. Every other prefix position is its own partner.
  @test.assert_eq(cert.witnesses.length(), 2)
  @test.assert_eq(cert.witnesses[0].proposer, 1)
  @test.assert_eq(cert.witnesses[0].receiver, 0)
  @test.assert_eq(cert.witnesses[0].holder, 2)
  @test.assert_eq(cert.witnesses[1].proposer, 1)
  @test.assert_eq(cert.witnesses[1].receiver, 1)
  @test.assert_eq(cert.witnesses[1].holder, 0)
  cert.verify() catch {
    e => fail("a stable certificate was rejected: \{e}")
  }
}

///|
test "certificates round-trip through JSON byte-for-byte" {
  let cert = fixture().deferred_acceptance().certificate()
  // The delivered blob is part of the API contract: pin its exact text.
  @test.assert_eq(cert.to_json_string(), market_json)
  let back = @moonmatch.StabilityCert::from_json_string(market_json) catch {
    e => fail("hand-written JSON was refused: \{e}")
  }
  @test.assert_eq(back, cert)
  back.verify() catch {
    e => fail("the round-tripped certificate was rejected: \{e}")
  }
}

///|
test "an outsider-built certificate with a missing witness is rejected" {
  let cert = @moonmatch.StabilityCert::from_json_string(blob("[1,2,0]", "[]")) catch {
    e => fail("parse failed: \{e}")
  }
  try (cert.verify() : Unit) catch {
    @moonmatch.MissingWitness(1, 0) => ()
    e => fail("expected MissingWitness(1, 0), got \{e}")
  } noraise {
    _ => fail("expected MissingWitness for P1's first-choice R0")
  }
}

///|
test "a dishonest witness is named exactly as the blocking pair it hides" {
  // Tampered claim [0,1,2]: P0 wants R1, R1 really holds P1 but ranks
  // P0 first — the false witness IS the blocking pair (P0, R1).
  let forged = blob(
    "[0,1,2]",
    "[" +
    w(0, 1, 1) +
    "," +
    w(1, 0, 0) +
    "," +
    w(2, 0, 0) +
    "," +
    w(2, 1, 1) +
    "]",
  )
  let cert = @moonmatch.StabilityCert::from_json_string(forged) catch {
    e => fail("parse failed: \{e}")
  }
  try (cert.verify() : Unit) catch {
    @moonmatch.WitnessNotDominating(0, 1) => ()
    e => fail("expected WitnessNotDominating(0, 1), got \{e}")
  } noraise {
    _ => fail("expected the lie to be caught")
  }
}

///|
test "a witness that misnames the holder fails the holder check first" {
  let cert = @moonmatch.StabilityCert::from_json_string(
    blob("[1,2,0]", "[" + w(1, 0, 0) + "]"),
  ) catch {
    e => fail("parse failed: \{e}")
  }
  try (cert.verify() : Unit) catch {
    @moonmatch.HolderMismatch(1, 0, 0, 2) => ()
    e => fail("expected HolderMismatch(1, 0, 0, 2), got \{e}")
  } noraise {
    _ => fail("expected the holder lie to be caught")
  }
}

///|
test "verify propagates structural errors from impossible claims untouched" {
  // claim [1,1,0] holds R1 twice — not a matching at all, so verify
  // refuses it via matching_from before any witness logic runs.
  let cert = @moonmatch.StabilityCert::from_json_string(blob("[1,1,0]", "[]")) catch {
    e => fail("parse failed: \{e}")
  }
  try (cert.verify() : Unit) catch {
    @moonmatch.ReceiverHeldTwice(1) => ()
    e => fail("expected ReceiverHeldTwice(1), got \{e}")
  } noraise {
    _ => fail("expected the impossible claim to be refused")
  }
}

///|
test "an out-of-range witness is rejected cleanly, not via a crash" {
  // A hostile blob naming receiver 9999 must produce a verdict, not
  // an array-index panic: this is the outsider-doors-must-not-crash
  // guarantee that JSON parsing alone cannot give.
  let cert = @moonmatch.StabilityCert::from_json_string(
    blob("[1,2,0]", "[" + w(1, 9999, 0) + "]"),
  ) catch {
    e => fail("parse failed: \{e}")
  }
  try (cert.verify() : Unit) catch {
    @moonmatch.InvalidWitness(1, 9999) => ()
    e => fail("expected InvalidWitness(1, 9999), got \{e}")
  } noraise {
    _ => fail("expected the out-of-range witness to be refused")
  }
}

///|
test "junk blobs are refused before any checking happens" {
  try
    (
      @moonmatch.StabilityCert::from_json_string("not json") :
      @moonmatch.StabilityCert)
  catch {
    _ => ()
  } noraise {
    _ => fail("expected a JSON error for non-JSON input")
  }
  try
    (
      @moonmatch.StabilityCert::from_json_string("[1,2,3]") :
      @moonmatch.StabilityCert)
  catch {
    _ => ()
  } noraise {
    _ => fail("expected a JSON error for an array-shaped certificate")
  }
}
