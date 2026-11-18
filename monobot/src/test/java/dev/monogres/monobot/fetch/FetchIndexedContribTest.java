package dev.monogres.monobot.fetch;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.monogres.monobot.digest.DigestUtils;
import dev.monogres.monobot.scan.Scan;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.io.IOException;
import java.net.URL;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/// A flavor that builds some of its contrib extensions out of a repository of its own (babelfish's
/// from babelfish_extensions) reports their control files in `contrib.json` beside its own, read
/// from the archive the download index next to the entry names for that version.
@QuarkusTest
@TestProfile(PipelineTestProfile.class)
class FetchIndexedContribTest {
  private static final String FLAVOR_DIR = "fixtureflavor";
  private static final String FLAVOR_URL =
      "https://github.com/monogres/fixtureflavor/archive/refs/tags/FLAVOR_5_4.tar.gz";
  private static final String EXT_URL =
      "https://github.com/monogres/fixture_extensions/archive/refs/tags/EXT_5_4.tar.gz";

  private static final String CONFIG =
      """
      {
        "name": "fixtureflavor",
        "type": "postgres",
        "sources": {
          "gh": {
            "filename": "{tag}",
            "url": "https://github.com/monogres/fixtureflavor/archive/refs/tags/{filename}.tar.gz",
            "strip_prefix": "fixtureflavor-{tag}"
          }
        },
        "versions": { "pin": { "5.4": { "tag": "FLAVOR_5_4" } } },
        "about": {
          "latest": {
            "description": "a fixture flavor",
            "license": "PostgreSQL",
            "contrib": {
              "fixture_tsql": {
                "description": "T-SQL",
                "license": "Apache-2.0",
                "repository": {
                  "url": "https://github.com/monogres/fixture_extensions",
                  "index": "ext.json"
                }
              }
            }
          }
        }%s
      }
      """;

  private static final String CORRECTION =
      """
      ,
        "control": {
          "5.4": {
            "fixture_tsql": {
              "default_version": "5.4.0",
              "module_pathname": "$libdir/fixture_tsql-5"
            }
          }
        }
      """;

  private static final String INDEX =
      """
      {
        "version": 1,
        "sources": {
          "gh": {
            "filename": "{tag}",
            "url": "https://github.com/monogres/fixture_extensions/archive/refs/tags/{filename}.tar.gz",
            "strip_prefix": "fixture_extensions-{tag}"
          }
        },
        "versions": { "5.4": { "tag": "EXT_5_4", "sha256": "%s" } }
      }
      """;

  @InjectMock SourceArchive sourceArchive;

  @Inject Scan scan;

  @Inject ObjectMapper objectMapper;

  private final Map<String, byte[]> archivesByUrl = new HashMap<>();

  private byte[] extArchive;

  @BeforeEach
  void setUp() throws Exception {
    PipelineFixture.resetTree();
    archivesByUrl.clear();

    var flavor = new LinkedHashMap<String, String>();
    flavor.put(
        "fixtureflavor-FLAVOR_5_4/contrib/amcheck/amcheck.control",
        "comment = 'verify'\ndefault_version = '1.5'\nrelocatable = true\n");
    archivesByUrl.put(FLAVOR_URL, PipelineFixture.archive(flavor, 0L));

    var ext = new LinkedHashMap<String, String>();
    ext.put(
        "fixture_extensions-EXT_5_4/contrib/fixture_tsql/fixture_tsql.control.in",
        """
        comment = 'Transact SQL compatibility'
        default_version = '@EXTVERSION@'
        module_pathname = '@MODULEPATH@'
        relocatable = true
        superuser = true
        requires = 'uuid-ossp, fixture_common'
        """);
    // Not one the override names, so not one the flavor reports.
    ext.put(
        "fixture_extensions-EXT_5_4/contrib/fixture_unit/fixture_unit.control",
        "default_version = '1.0.0'\n");
    extArchive = PipelineFixture.archive(ext, 0L);
    archivesByUrl.put(EXT_URL, extArchive);

    when(sourceArchive.download(any(), any()))
        .thenAnswer(
            invocation -> {
              URL url = invocation.getArgument(0);
              Path target = invocation.getArgument(1);
              var bytes = archivesByUrl.get(url.toString());
              assertNotNull(bytes, "no archive registered for " + url);
              return PipelineFixture.served(target, bytes);
            });
  }

  private void write(String correction, String sha256) throws IOException {
    PipelineFixture.writeConfig(FLAVOR_DIR, CONFIG.formatted(correction));
    Files.writeString(
        PipelineFixture.CATALOG_DIR.resolve(FLAVOR_DIR).resolve("ext.json"),
        INDEX.formatted(sha256));
  }

  private void run() throws Exception {
    scan.run().toCompletionStage().toCompletableFuture().get(60, TimeUnit.SECONDS);
  }

  private JsonNode read(String path) throws IOException {
    return objectMapper.readTree(
        PipelineFixture.CATALOG_DIR.resolve(FLAVOR_DIR).resolve(path).toFile());
  }

  private String extSha256() {
    return DigestUtils.sha256sum(ByteBuffer.wrap(extArchive));
  }

  @Test
  void indexedContribIsReportedBesideTheFlavorsOwn() throws Exception {
    write(CORRECTION, extSha256());

    run();

    var contrib = read("metadata/5.4/contrib.json");
    assertEquals("1.5", contrib.path("amcheck").path("default_version").asText());
    assertEquals("@EXTVERSION@", contrib.path("fixture_tsql").path("default_version").asText());
    assertTrue(contrib.path("fixture_unit").isMissingNode(), contrib.toString());

    var about = read("about.json").path("latest").path("contrib");
    assertEquals(
        objectMapper.readTree(
            """
            {"fixture_tsql": {"default_version": "5.4.0",
                              "module_pathname": "$libdir/fixture_tsql-5",
                              "requires": ["uuid-ossp", "fixture_common"],
                              "superuser": true, "trusted": false, "relocatable": true}}
            """),
        about.path("fixture_tsql").path("control"));
    assertEquals("EXT_5_4", about.path("fixture_tsql").path("ref").asText());

    // Kept under the entry, apart from the flavor's own archive.
    assertTrue(
        Files.exists(PipelineFixture.cached(FLAVOR_DIR + "/ext", "5.4").resolve("EXT_5_4.tar.gz")));
  }

  /// A placeholder nothing corrected is the entry's to fix, as it is for an extension's own.
  @Test
  void uncorrectedTemplateFailsTheEntry() throws Exception {
    write("", extSha256());

    assertThrows(ExecutionException.class, this::run);
    assertTrue(
        Files.notExists(PipelineFixture.CATALOG_DIR.resolve(FLAVOR_DIR).resolve("about.json")));
  }

  /// An archive that is not what the index records is not read.
  @Test
  void archiveDisagreeingWithItsIndexIsNotRead() throws Exception {
    write(CORRECTION, "0".repeat(64));

    assertThrows(ExecutionException.class, this::run);
    var contrib = read("metadata/5.4/contrib.json");
    assertTrue(contrib.path("fixture_tsql").isMissingNode(), contrib.toString());
  }
}
