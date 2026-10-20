package dev.monogres.monobot.fetch;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.monogres.monobot.about.Forge;
import dev.monogres.monobot.about.Layers;
import dev.monogres.monobot.about.UpstreamClient;
import dev.monogres.monobot.about.UpstreamClient.UpstreamException;
import dev.monogres.monobot.git.TagLister;
import dev.monogres.monobot.scan.Scan;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/// What an entry says about itself to a reader: the snapshot of what its upstream answered, taken
/// once and committed, and the `about.json` derived from that snapshot and the archive.
///
/// The upstream is mocked. What is under test is when it is asked, what is kept of the answer, that
/// a run with a snapshot in hand asks it nothing, and how each version keeps its own.
@QuarkusTest
@TestProfile(ScrapeUpstreamTestProfile.class)
class FetchAboutTest {
  private static final String EXTENSION_DIR = "extensions/fixture";
  private static final Forge FORGE = new Forge(Forge.Kind.GITHUB, "monogres/fixture");

  private static final String CONFIG =
      """
      {
        "name": "fixture",
        "url": "https://github.com/monogres/fixture",
        "sources": {
          "gh": {
            "tag": "v{version}",
            "name": "fixture",
            "strip_prefix": "{name}-{version}",
            "url": "https://github.com/monogres/{name}/archive/refs/tags/{tag}.tar.gz"
          }
        },
        "versions": { "pin": %s }%s
      }
      """;

  private static final Pattern TAG = Pattern.compile("/v([^/]+)\\.tar\\.gz$");

  @InjectMock TagLister tagLister;

  @InjectMock SourceArchive sourceArchive;

  @InjectMock UpstreamClient upstreamClient;

  @Inject Scan scan;

  @Inject ObjectMapper objectMapper;

  @BeforeEach
  void setUp() throws Exception {
    PipelineFixture.resetTree();
    configure("[\"1.0.0\"]", "");

    // Every version serves an archive of its own, named the way `strip_prefix` expects it.
    when(sourceArchive.download(any(), any()))
        .thenAnswer(
            invocation -> {
              URL url = invocation.getArgument(0);
              Path target = invocation.getArgument(1);
              var matcher = TAG.matcher(url.getPath());
              assertTrue(matcher.find(), "not a tag archive: " + url);
              var version = matcher.group(1);

              return PipelineFixture.served(
                  target,
                  PipelineFixture.controlArchive(
                      "fixture",
                      "fixture-" + version,
                      PipelineFixture.control(version, "a fixture extension"),
                      0L));
            });
    when(upstreamClient.repository(any())).thenReturn(Optional.of(repository("the forge about")));
    when(upstreamClient.readme(any(), any())).thenReturn(Optional.of("README.md"));
  }

  static void configure(String pin, String about) throws Exception {
    PipelineFixture.writeConfig(EXTENSION_DIR, CONFIG.formatted(pin, about));
  }

  ObjectNode repository(String description) throws Exception {
    return (ObjectNode)
        objectMapper.readTree(
            """
            {
              "kind": "github",
              "url": "https://github.com/monogres/fixture",
              "description": "%s",
              "homepage": null,
              "license": "MIT",
              "topics": ["fixtures"]
            }
            """
                .formatted(description));
  }

  private void run() throws Exception {
    scan.run().toCompletionStage().toCompletableFuture().get(60, TimeUnit.SECONDS);
  }

  private Path entryDir() {
    return PipelineFixture.repoJson(EXTENSION_DIR).getParent();
  }

  private Path upstreamJson() {
    return entryDir().resolve("metadata/upstream.json");
  }

  private Path aboutJson() {
    return entryDir().resolve("about.json");
  }

  private JsonNode read(Path file) throws Exception {
    return objectMapper.readTree(file.toFile());
  }

  @Test
  void generateSnapshotsTheUpstreamAndDerivesAbout() throws Exception {
    run();

    assertEquals(
        objectMapper.readTree(
            """
            {
              "latest": {
                "version": "1.0.0",
                "forge": {
                  "kind": "github",
                  "url": "https://github.com/monogres/fixture",
                  "description": "the forge about",
                  "license": "MIT",
                  "topics": ["fixtures"],
                  "readme": "README.md"
                }
              }
            }
            """),
        read(upstreamJson()));

    assertEquals(
        objectMapper.readTree(
            """
            {
              "latest": {
                "version": "1.0.0",
                "description": "a fixture extension",
                "long_description": "the forge about",
                "homepage": "https://github.com/monogres/fixture",
                "license": "MIT",
                "keywords": ["fixtures"],
                "repository": {"url": "https://github.com/monogres/fixture"},
                "ref": "v1.0.0",
                "readme": "https://raw.githubusercontent.com/monogres/fixture/v1.0.0/README.md",
                "control": {"default_version": "1.0.0", "superuser": true, "trusted": false, "relocatable": false}
              }
            }
            """),
        read(aboutJson()));
    verify(upstreamClient).repository(FORGE);
  }

  /// A forge only answers about the repository as it is now, so a version keeps the answer from
  /// when it was catalogued: a new version is asked about alone, and the older one is not asked
  /// again even though the forge has since changed its mind.
  @Test
  void newVersionIsAskedAboutAloneAndOlderOnesStayFrozen() throws Exception {
    run();
    clearInvocations(upstreamClient);
    when(upstreamClient.repository(any())).thenReturn(Optional.of(repository("a newer about")));
    configure("[\"1.0.0\", \"1.1.0\"]", "");

    run();

    verify(upstreamClient).repository(FORGE);
    verify(upstreamClient).readme(any(), eq("v1.1.0"));
    verify(upstreamClient, never()).readme(any(), eq("v1.0.0"));
    var upstream = read(upstreamJson());
    assertEquals("1.1.0", upstream.path("latest").path("version").asText());
    assertEquals(
        objectMapper.readTree("{\"1.0.0\": {\"forge\": {\"description\": \"the forge about\"}}}"),
        upstream.path("versions"));

    assertEquals(
        objectMapper.readTree(
            """
            {
              "latest": {
                "version": "1.1.0",
                "description": "a fixture extension",
                "long_description": "a newer about",
                "homepage": "https://github.com/monogres/fixture",
                "license": "MIT",
                "keywords": ["fixtures"],
                "repository": {"url": "https://github.com/monogres/fixture"},
                "ref": "v1.1.0",
                "readme": "https://raw.githubusercontent.com/monogres/fixture/v1.1.0/README.md",
                "control": {"default_version": "1.1.0", "superuser": true, "trusted": false, "relocatable": false}
              },
              "versions": {
                "1.0.0": {
                  "long_description": "the forge about",
                  "ref": "v1.0.0",
                  "readme": "https://raw.githubusercontent.com/monogres/fixture/v1.0.0/README.md",
                  "control": {"default_version": "1.0.0"}
                }
              }
            }
            """),
        read(aboutJson()));
  }

  /// The override's `latest` is the newest version's, and a patch keyed on a version applies to it
  /// and to every older one.
  @Test
  void versionedOverrideAppliesToItsVersionAndOlder() throws Exception {
    configure(
        "[\"0.9.0\", \"1.0.0\", \"1.1.0\"]",
        """
        ,
        "about": {
          "latest": {"description": "now", "categories": ["FIXTURE"]},
          "versions": {"1.0.0": {"description": "then"}}
        }
        """);

    run();

    var about = read(aboutJson());
    assertEquals("now", about.path("latest").path("description").asText());
    assertEquals(
        objectMapper.readTree(
            """
            {
              "1.0.0": {
                "description": "then",
                "ref": "v1.0.0",
                "readme": "https://raw.githubusercontent.com/monogres/fixture/v1.0.0/README.md",
                "control": {"default_version": "1.0.0"}
              },
              "0.9.0": {
                "ref": "v0.9.0",
                "readme": "https://raw.githubusercontent.com/monogres/fixture/v0.9.0/README.md",
                "control": {"default_version": "0.9.0"}
              }
            }
            """),
        about.path("versions"));
  }

  /// A control correction is the control file of one release, so it applies to that version and
  /// to no other, older or newer.
  @Test
  void controlCorrectionAppliesToItsVersionAlone() throws Exception {
    configure(
        "[\"0.9.0\", \"1.0.0\", \"1.1.0\"]",
        """
        ,
        "control": {"1.0.0": {"default_version": "1.0"}}
        """);

    run();

    var resolved = Layers.resolve(read(aboutJson()));
    assertEquals("1.1.0", resolved.get("1.1.0").path("control").path("default_version").asText());
    assertEquals("1.0", resolved.get("1.0.0").path("control").path("default_version").asText());
    assertEquals("0.9.0", resolved.get("0.9.0").path("control").path("default_version").asText());
  }

  /// A correction keyed on a version nothing catalogues corrects nothing, so it fails the entry
  /// rather than being dropped.
  @Test
  void controlCorrectionOfAnUncataloguedVersionFailsTheEntry() throws Exception {
    configure(
        "[\"1.0.0\"]",
        """
        ,
        "control": {"1.0": {"default_version": "1.0"}}
        """);

    var failure = assertThrows(ExecutionException.class, this::run);

    assertTrue(
        failure.getMessage().contains("control.1.0 corrects a version that is not catalogued"),
        "the failure does not say what happened: " + failure.getMessage());
  }

  /// The snapshot is the answer, so the run after the one that took it asks nothing and writes the
  /// same bytes. That is what lets `check` run offline.
  @Test
  void secondRunAsksNothingAndWritesTheSame() throws Exception {
    run();
    final var upstream = Files.readString(upstreamJson());
    final var about = Files.readString(aboutJson());
    clearInvocations(upstreamClient);

    run();

    verifyNoInteractions(upstreamClient);
    assertEquals(upstream, Files.readString(upstreamJson()));
    assertEquals(about, Files.readString(aboutJson()));
  }

  /// A rate limit is not the forge saying the project has no description, so a refusal fails the
  /// entry and commits nothing that would read as an answer.
  @Test
  void anUpstreamThatCannotBeAskedFailsTheEntry() throws Exception {
    when(upstreamClient.repository(any()))
        .thenThrow(new UpstreamException("answered 403: rate limited", null));

    var failure = assertThrows(ExecutionException.class, this::run);

    assertEquals(
        true,
        failure.getMessage().contains("upstream could not be asked"),
        "the failure does not say what happened: " + failure.getMessage());
    assertFalse(Files.exists(aboutJson()), "about.json was written from a refused answer");
    assertFalse(Files.exists(upstreamJson()), "a refused answer was snapshotted");
  }
}
