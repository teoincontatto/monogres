package dev.monogres.monobot.fetch;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.monogres.monobot.about.Forge;
import dev.monogres.monobot.about.UpstreamClient;
import dev.monogres.monobot.about.UpstreamClient.UpstreamException;
import dev.monogres.monobot.git.TagLister;
import dev.monogres.monobot.scan.Scan;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/// What an entry says about itself to a reader: the snapshot of what its upstream answered, taken
/// once and committed, and the `about.json` derived from that snapshot and the archive.
///
/// The upstream is mocked. What is under test is when it is asked, what is kept of the answer, and
/// that a run with a snapshot in hand asks it nothing.
@QuarkusTest
@TestProfile(ScrapeUpstreamTestProfile.class)
class FetchAboutTest {
  private static final String EXTENSION_DIR = "extensions/fixture";
  private static final String VERSION = "1.0.0";
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
        "versions": { "pin": ["1.0.0"] }
      }
      """;

  @InjectMock TagLister tagLister;

  @InjectMock SourceArchive sourceArchive;

  @InjectMock UpstreamClient upstreamClient;

  @Inject Scan scan;

  @Inject ObjectMapper objectMapper;

  @BeforeEach
  void setUp() throws Exception {
    PipelineFixture.resetTree();
    PipelineFixture.writeConfig(EXTENSION_DIR, CONFIG);

    when(sourceArchive.download(any(), any()))
        .thenAnswer(
            invocation -> {
              Path target = invocation.getArgument(1);

              return PipelineFixture.served(
                  target,
                  PipelineFixture.controlArchive(
                      "fixture",
                      "fixture-" + VERSION,
                      PipelineFixture.control(VERSION, "a fixture extension"),
                      0L));
            });
    when(upstreamClient.repository(any())).thenReturn(Optional.of(repository()));
    when(upstreamClient.readme(any(), eq("v" + VERSION))).thenReturn(Optional.of("README.md"));
  }

  private ObjectNode repository() throws Exception {
    return (ObjectNode)
        objectMapper.readTree(
            """
            {
              "kind": "github",
              "url": "https://github.com/monogres/fixture",
              "description": "the forge about",
              "homepage": null,
              "license": "MIT",
              "topics": ["fixtures"]
            }
            """);
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

    var upstream = read(upstreamJson());
    assertEquals("the forge about", upstream.path("forge").path("description").asText());
    assertEquals("README.md", upstream.path("forge").path("readme").path("v1.0.0").asText());
    assertEquals(1, upstream.size(), "the snapshot holds more than the forge: " + upstream);

    assertEquals(
        objectMapper.readTree(
            """
            {
              "description": "a fixture extension",
              "long_description": "the forge about",
              "homepage": "https://github.com/monogres/fixture",
              "license": "MIT",
              "keywords": ["fixtures"],
              "repository": {"url": "https://github.com/monogres/fixture"},
              "versions": {
                "1.0.0": {
                  "ref": "v1.0.0",
                  "readme": "https://raw.githubusercontent.com/monogres/fixture/v1.0.0/README.md"
                }
              }
            }
            """),
        read(aboutJson()));
    verify(upstreamClient).repository(FORGE);
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
