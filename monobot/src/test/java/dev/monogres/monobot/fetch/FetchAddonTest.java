package dev.monogres.monobot.fetch;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.monogres.monobot.digest.DigestUtils;
import dev.monogres.monobot.scan.Scan;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/// An addon is catalogued for its digest and its `about.json`, and its archive is never walked:
/// kubectl's is the whole Kubernetes tree, far past what the extractor lets an archive expand to.
/// So an archive that is not an archive at all still catalogues.
@QuarkusTest
@TestProfile(PipelineTestProfile.class)
class FetchAddonTest {
  private static final String ADDON_DIR = "addons/fixture";
  private static final byte[] NOT_AN_ARCHIVE =
      "a binary, not a tarball".getBytes(StandardCharsets.UTF_8);

  private static final String CONFIG =
      """
      {
        "name": "fixture",
        "type": "addon",
        "url": "https://github.com/monogres/fixture",
        "sources": {
          "gh": {
            "tag": "v{version}",
            "url": "https://github.com/monogres/fixture/archive/refs/tags/{tag}.tar.gz"
          }
        },
        "versions": { "pin": ["1.0.0"] },
        "about": { "latest": { "description": "a fixture addon" } }
      }
      """;

  @InjectMock SourceArchive sourceArchive;

  @Inject Scan scan;

  @Inject ObjectMapper objectMapper;

  @BeforeEach
  void setUp() throws Exception {
    PipelineFixture.resetTree();
    PipelineFixture.writeConfig(ADDON_DIR, CONFIG);

    when(sourceArchive.download(any(), any()))
        .thenAnswer(
            invocation -> PipelineFixture.served(invocation.getArgument(1), NOT_AN_ARCHIVE));
  }

  @Test
  void anAddonIsDigestedAndDescribedWithoutBeingRead() throws Exception {
    scan.run().toCompletionStage().toCompletableFuture().get(60, TimeUnit.SECONDS);

    var entryDir = PipelineFixture.repoJson(ADDON_DIR).getParent();
    var repo = objectMapper.readTree(PipelineFixture.repoJson(ADDON_DIR).toFile());
    assertEquals(
        DigestUtils.sha256sum(ByteBuffer.wrap(NOT_AN_ARCHIVE)),
        repo.path("versions").path("1.0.0").path("sha256").asText());

    var about = objectMapper.readTree(entryDir.resolve("about.json").toFile());
    assertEquals("1.0.0", about.path("latest").path("version").asText());
    assertEquals("a fixture addon", about.path("latest").path("description").asText());
    assertEquals("v1.0.0", about.path("latest").path("ref").asText());

    assertFalse(
        Files.exists(entryDir.resolve("metadata").resolve("1.0.0")),
        "an addon's archive was read for what it carries");
  }
}
