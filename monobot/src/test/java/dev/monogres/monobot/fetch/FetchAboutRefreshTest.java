package dev.monogres.monobot.fetch;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.monogres.monobot.about.UpstreamClient;
import dev.monogres.monobot.git.TagLister;
import dev.monogres.monobot.scan.Scan;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.net.URL;
import java.nio.file.Path;
import java.util.Optional;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/// `refreshUpstream` is how a changed description reaches the catalog, and it reaches only the
/// newest version: the older ones keep what the forge said when they were catalogued.
@QuarkusTest
@TestProfile(RefreshUpstreamTestProfile.class)
class FetchAboutRefreshTest {
  private static final String EXTENSION_DIR = "extensions/fixture";
  private static final Pattern TAG = Pattern.compile("/v([^/]+)\\.tar\\.gz$");

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
        "versions": { "pin": ["1.0.0", "1.1.0"] }
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
              URL url = invocation.getArgument(0);
              Path target = invocation.getArgument(1);
              var matcher = TAG.matcher(url.getPath());
              matcher.find();
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

  private ObjectNode repository(String description) throws Exception {
    return (ObjectNode)
        objectMapper.readTree(
            """
            {"kind": "github", "url": "https://github.com/monogres/fixture", "description": "%s"}
            """
                .formatted(description));
  }

  private void run() throws Exception {
    scan.run().toCompletionStage().toCompletableFuture().get(60, TimeUnit.SECONDS);
  }

  @Test
  void refreshAsksAgainAboutTheNewestVersionOnly() throws Exception {
    run();
    clearInvocations(upstreamClient);
    when(upstreamClient.repository(any())).thenReturn(Optional.of(repository("a newer about")));

    run();

    verify(upstreamClient).readme(any(), eq("v1.1.0"));
    verify(upstreamClient, never()).readme(any(), eq("v1.0.0"));
    var entryDir = PipelineFixture.repoJson(EXTENSION_DIR).getParent();
    var about = objectMapper.readTree(entryDir.resolve("about.json").toFile());
    assertEquals("a newer about", about.path("latest").path("long_description").asText());
    assertEquals(
        "the forge about", about.path("versions").path("1.0.0").path("long_description").asText());
  }
}
