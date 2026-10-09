package dev.monogres.monobot.about;

import static org.junit.jupiter.api.Assertions.assertEquals;

import dev.monogres.monobot.about.Forge.Kind;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/// Which repository a URL names, whichever way the catalog or a META.json happened to spell it.
class ForgeTest {

  @Test
  void githubRepository() {
    assertEquals(
        Optional.of(new Forge(Kind.GITHUB, "pgvector/pgvector")),
        Forge.of("https://github.com/pgvector/pgvector"));
  }

  /// META.json's `resources.repository.url` is the clone URL.
  @Test
  void gitSuffixIsTheSameRepository() {
    assertEquals(
        Optional.of(new Forge(Kind.GITHUB, "pgvector/pgvector")),
        Forge.of("https://github.com/pgvector/pgvector.git"));
  }

  @Test
  void treeLinkIsTheRepositoryItIsIn() {
    assertEquals(
        Optional.of(new Forge(Kind.GITHUB, "postgis/postgis")),
        Forge.of("https://github.com/postgis/postgis/tree/master/doc/"));
  }

  @Test
  void githubOwnerAloneIsNoRepository() {
    assertEquals(Optional.empty(), Forge.of("https://github.com/pgvector"));
  }

  /// A GitLab project can sit in nested groups, so the whole path is the project.
  @Test
  void gitlabNestedGroups() {
    assertEquals(
        Optional.of(new Forge(Kind.GITLAB, "ongresinc/extensions/noset")),
        Forge.of("https://gitlab.com/ongresinc/extensions/noset"));
  }

  @Test
  void gitlabLinkAfterTheSeparatorIsTheProject() {
    assertEquals(
        Optional.of(new Forge(Kind.GITLAB, "ongresinc/pg_healpix")),
        Forge.of("https://gitlab.com/ongresinc/pg_healpix/-/blob/main/README.md"));
  }

  @Test
  void otherHostsAreNotForges() {
    assertEquals(Optional.empty(), Forge.of("https://download.osgeo.org/postgis/source/"));
    assertEquals(Optional.empty(), Forge.of("https://pgxn.org/dist/short_ids"));
    assertEquals(Optional.empty(), Forge.of("not a url"));
    assertEquals(Optional.empty(), Forge.of(""));
    assertEquals(Optional.empty(), Forge.of(null));
  }

  @Test
  void githubUrls() {
    var forge = new Forge(Kind.GITHUB, "pgvector/pgvector");

    assertEquals("https://github.com/pgvector/pgvector", forge.webUrl());
    assertEquals(
        "https://raw.githubusercontent.com/pgvector/pgvector/v0.8.2/README.md",
        forge.rawUrl("v0.8.2", "README.md"));
  }

  @Test
  void gitlabUrls() {
    var forge = new Forge(Kind.GITLAB, "ongresinc/extensions/noset");

    assertEquals("https://gitlab.com/ongresinc/extensions/noset", forge.webUrl());
    assertEquals(
        "https://gitlab.com/ongresinc/extensions/noset/-/raw/v1.0/README.md",
        forge.rawUrl("v1.0", "README.md"));
  }
}
