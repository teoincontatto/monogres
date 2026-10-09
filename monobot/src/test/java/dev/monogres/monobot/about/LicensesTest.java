package dev.monogres.monobot.about;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/// Every source spells a licence its own way, and the catalog spells it one way: SPDX. An answer
/// that names no licence has to come back empty rather than as a string, or it would win over the
/// next source that does name one.
class LicensesTest {
  private final ObjectMapper objectMapper = new ObjectMapper();

  /// What GitHub's detector says of a licence it cannot place, PostgreSQL's own among them.
  @Test
  void noAssertionSaysNothing() {
    assertEquals(Optional.empty(), Licenses.of("NOASSERTION"));
  }

  @Test
  void unknownSaysNothing() {
    assertEquals(Optional.empty(), Licenses.of("Unknown"));
  }

  @Test
  void blankSaysNothing() {
    assertEquals(Optional.empty(), Licenses.of("  "));
    assertEquals(Optional.empty(), Licenses.of(null));
  }

  /// GitLab's key is lowercase and not quite SPDX.
  @Test
  void gitlabKeyIsSpdx() {
    assertEquals(Optional.of("AGPL-3.0"), Licenses.of("agpl-3.0"));
  }

  @Test
  void spdxIdPassesThrough() {
    assertEquals(Optional.of("Apache-2.0"), Licenses.of("Apache-2.0"));
  }

  /// A spelling no table knows is still a better answer than none, so it is kept, stripped.
  @Test
  void unknownSpellingPassesThroughStripped() {
    assertEquals(Optional.of("Timescale"), Licenses.of("  Timescale "));
  }

  @Test
  void pgxnString() throws Exception {
    assertEquals(
        Optional.of("PostgreSQL"), Licenses.ofPgxn(objectMapper.readTree("\"postgresql\"")));
  }

  /// A map's keys are the licences; the URLs are where to read them.
  @Test
  void pgxnMap() throws Exception {
    assertEquals(
        Optional.of("PostgreSQL"),
        Licenses.ofPgxn(
            objectMapper.readTree(
                "{\"PostgreSQL\": \"http://www.postgresql.org/about/licence\"}")));
  }

  /// More than one licence in PGXN is a choice between them, which SPDX spells with OR.
  @Test
  void pgxnArrayIsChoice() throws Exception {
    assertEquals(
        Optional.of("MIT OR BSD-3-Clause"),
        Licenses.ofPgxn(objectMapper.readTree("[\"mit\", \"bsd\"]")));
  }

  @Test
  void pgxnArrayOfUnknownsSaysNothing() throws Exception {
    assertEquals(
        Optional.empty(), Licenses.ofPgxn(objectMapper.readTree("[\"unknown\", \"restricted\"]")));
  }

  @Test
  void pgxnAbsentSaysNothing() {
    assertEquals(Optional.empty(), Licenses.ofPgxn(null));
    assertEquals(Optional.empty(), Licenses.ofPgxn(objectMapper.nullNode()));
    assertEquals(Optional.empty(), Licenses.ofPgxn(objectMapper.missingNode()));
  }
}
