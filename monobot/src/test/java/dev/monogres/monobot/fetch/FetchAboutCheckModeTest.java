package dev.monogres.monobot.fetch;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.monogres.monobot.about.UpstreamClient;
import dev.monogres.monobot.digest.DigestUtils;
import dev.monogres.monobot.git.TagLister;
import dev.monogres.monobot.json.DocumentWriter;
import dev.monogres.monobot.scan.Scan;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/// `check` derives `about.json` from the committed snapshot and nothing else. It never asks the
/// upstream, whether the snapshot is there or not, so the gate runs offline and cannot be failed
/// by a forge changing its mind.
@QuarkusTest
@TestProfile(CheckModeTestProfile.class)
class FetchAboutCheckModeTest {
  private static final String EXTENSION_DIR = "extensions/fixture";
  private static final String VERSION = "1.0.0";

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

  private static final String REPO_JSON =
      """
      {
        "version": 1,
        "sources": {
          "gh": {
            "tag": "v{version}",
            "name": "fixture",
            "strip_prefix": "{name}-{version}",
            "url": "https://github.com/monogres/{name}/archive/refs/tags/{tag}.tar.gz"
          }
        },
        "versions": {"1.0.0": {"sha256": "%s"}},
        "metadata": {}
      }
      """;

  private static final String UPSTREAM_JSON =
      """
      {
        "latest": {
          "version": "1.0.0",
          "forge": {
            "kind": "github",
            "url": "https://github.com/monogres/fixture",
            "description": "the forge about",
            "license": "MIT",
            "topics": [],
            "readme": "README.md"
          }
        }
      }
      """;

  private static final String ABOUT_JSON =
      """
      {
        "latest": {
          "version": "1.0.0",
          "description": "a fixture extension",
          "long_description": "the forge about",
          "homepage": "https://github.com/monogres/fixture",
          "license": "MIT",
          "repository": {"url": "https://github.com/monogres/fixture"},
          "ref": "v1.0.0",
          "readme": "https://raw.githubusercontent.com/monogres/fixture/v1.0.0/README.md",
          "control": {
            "fixture": {
              "default_version": "1.0.0",
              "superuser": true,
              "trusted": false,
              "relocatable": false
            }
          }
        }
      }
      """;

  @InjectMock TagLister tagLister;

  @InjectMock SourceArchive sourceArchive;

  @InjectMock UpstreamClient upstreamClient;

  @Inject Scan scan;

  @Inject ObjectMapper objectMapper;

  @Inject DocumentWriter documentWriter;

  @Inject ArchiveMetadataExtractor extractor;

  @BeforeEach
  void setUp() throws Exception {
    PipelineFixture.resetTree();
    PipelineFixture.writeConfig(EXTENSION_DIR, CONFIG);

    when(sourceArchive.download(any(), any()))
        .thenAnswer(
            invocation -> {
              Path target = invocation.getArgument(1);

              return PipelineFixture.served(target, archiveBytes());
            });
  }

  private static String controlText() {
    return PipelineFixture.control(VERSION, "a fixture extension");
  }

  private static byte[] archiveBytes() throws Exception {
    return PipelineFixture.controlArchive("fixture", "fixture-" + VERSION, controlText(), 0L);
  }

  private void run() throws Exception {
    scan.run().toCompletionStage().toCompletableFuture().get(60, TimeUnit.SECONDS);
  }

  private Path entryDir() {
    return PipelineFixture.repoJson(EXTENSION_DIR).getParent();
  }

  /// Each document as the catalog prints it, so what is committed is byte for byte what a
  /// generate run would have written.
  private void commit(Path file, String json) throws Exception {
    Files.createDirectories(file.getParent());
    Files.writeString(file, documentWriter.render(objectMapper.readTree(json)));
  }

  private void commitTheCatalogue() throws Exception {
    var digest = DigestUtils.sha256sum(ByteBuffer.wrap(archiveBytes()));
    commit(PipelineFixture.repoJson(EXTENSION_DIR), REPO_JSON.formatted(digest));
    var control = extractor.controlOf(controlText().getBytes(StandardCharsets.UTF_8)).toString();
    commit(entryDir().resolve("metadata/1.0.0/control.json"), "{\"fixture\": " + control + "}");
    commit(entryDir().resolve("metadata/upstream.json"), UPSTREAM_JSON);
    commit(entryDir().resolve("about.json"), ABOUT_JSON);
  }

  @Test
  void theCommittedSnapshotAnswersWithoutAsking() throws Exception {
    commitTheCatalogue();

    run();

    verifyNoInteractions(upstreamClient);
  }

  /// A snapshot that changed is a description that changed, and the committed about.json no
  /// longer follows from it.
  @Test
  void aboutJsonThatNoLongerFollowsFails() throws Exception {
    commitTheCatalogue();
    commit(
        entryDir().resolve("metadata/upstream.json"),
        UPSTREAM_JSON.replace("the forge about", "something else"));

    var failure = assertThrows(ExecutionException.class, this::run);

    assertTrue(
        failure.getMessage().contains("differ from what is committed"),
        "the failure does not say what happened: " + failure.getMessage());
    verifyNoInteractions(upstreamClient);
  }

  /// With no snapshot at all, check still does not go and take one.
  @Test
  void noSnapshotIsNotTakenByCheck() throws Exception {
    assertThrows(ExecutionException.class, this::run);

    verifyNoInteractions(upstreamClient);
    assertFalse(Files.exists(entryDir().resolve("metadata/upstream.json")));
    assertEquals(false, Files.exists(entryDir().resolve("about.json")));
  }
}
