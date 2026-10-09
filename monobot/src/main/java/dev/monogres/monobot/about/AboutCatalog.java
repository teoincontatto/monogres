package dev.monogres.monobot.about;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.monogres.monobot.catalog.SourceTemplate;
import dev.monogres.monobot.config.Mode;
import dev.monogres.monobot.config.input.MonobotConfig;
import dev.monogres.monobot.config.output.RepoConfig;
import dev.monogres.monobot.config.output.Version;
import dev.monogres.monobot.config.output.Versions;
import dev.monogres.monobot.json.DocumentWriter;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.SequencedMap;
import java.util.TreeMap;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/// The two halves of what an entry says about itself to a reader: a snapshot of what its upstream
/// says, and the `about.json` derived from it.
///
/// They are kept apart on purpose. The snapshot, `metadata/upstream.json`, is the only part that
/// comes off the network, and it is committed: what the forge answered is then a reviewable diff
/// rather than something a run happened to see, and `check` re-derives `about.json` from it without
/// a request. A snapshot is taken when an entry has none, when a version brings a ref whose README
/// has not been looked for, and on every entry when `refreshUpstream` asks for it.
@ApplicationScoped
public class AboutCatalog {
  private static final Logger LOG = Logger.getLogger(AboutCatalog.class);

  private static final String DIR_METADATA = "metadata";
  private static final String FILENAME_ABOUT = "about.json";
  private static final String FILENAME_UPSTREAM = "upstream.json";
  private static final String FILENAME_CONTROL = "control.json";
  private static final String FILENAME_META = "META.json";
  private static final String FILENAME_CONTRIB = "contrib.json";

  private static final String KEY_FORGE = "forge";
  private static final String KEY_README = "readme";

  @ConfigProperty(name = "mode")
  Mode mode;

  @ConfigProperty(name = "scrapeUpstream")
  boolean scrapeUpstream;

  @ConfigProperty(name = "refreshUpstream")
  boolean refreshUpstream;

  @Inject UpstreamClient upstreamClient;

  @Inject ObjectMapper objectMapper;

  @Inject DocumentWriter documentWriter;

  public static String filename() {
    return FILENAME_ABOUT;
  }

  /// The document for one entry, or empty when nothing describes it: an entry with no
  /// description and no repository has nothing a reader could use, and writing one anyway would
  /// add a file to every fixture that never asked for it.
  public Optional<ObjectNode> about(MonobotConfig monobotConfig, Path entryDir, Versions versions) {
    var override = monobotConfig.about();
    var refs = refs(monobotConfig, versions);
    var newest = versions.keySet().stream().max(Comparator.naturalOrder());
    var control = newest.map(version -> read(entryDir, version, FILENAME_CONTROL)).orElse(null);
    var meta = newest.map(version -> read(entryDir, version, FILENAME_META)).orElse(null);
    var contrib = contrib(entryDir, versions);

    var upstream = snapshot(monobotConfig, entryDir, override, meta, refs);

    var about =
        AboutResolver.resolve(
            objectMapper,
            new AboutResolver.Inputs(
                override,
                control,
                meta,
                upstream,
                monobotConfig.repoUrl() == null ? null : monobotConfig.repoUrl().toString(),
                refs,
                contrib,
                contribRefs(monobotConfig, entryDir, override)));

    if (!about.has("description") && !about.has("repository")) {
      return Optional.empty();
    }

    return Optional.of(about);
  }

  /// The ref each version's archive was cut from, in the order the versions are catalogued.
  ///
  /// Spelled by the override's `repository.ref` template where there is one, which is how an entry
  /// whose archives come from somewhere other than its repository (postgis) names its tags.
  /// Otherwise it is the `tag` or the `commit` the source materializes to, which is what every
  /// forge-hosted entry already has, and a version with neither has no ref.
  private SequencedMap<String, String> refs(MonobotConfig monobotConfig, Versions versions) {
    var template = monobotConfig.sources().templates().getFirst();
    var refTemplate = monobotConfig.about().path("repository").path("ref");
    var refs = new LinkedHashMap<String, String>();

    versions.forEach(
        (version, context) -> {
          var materialized = template.materialize(version.version(), context.derived());
          String ref;
          if (refTemplate.isTextual()) {
            var spelled = new LinkedHashMap<String, String>();
            spelled.put("ref", refTemplate.asText());
            ref =
                new SourceTemplate(template.source(), spelled)
                    .materialize(version.version(), materialized)
                    .get("ref");
          } else {
            ref = materialized.getOrDefault("tag", materialized.get("commit"));
          }
          refs.put(version.version(), ref);
        });

    return refs;
  }

  /// The refs of the contrib extensions a flavor builds out of a repository of its own, by flavor
  /// version. The override names that repository's download index beside the entry
  /// (`"repository": {"url": ..., "index": "ext.json"}`), which is what the build fetches those
  /// sources from, so the ref each flavor version builds is read rather than written twice.
  private Map<String, SequencedMap<String, String>> contribRefs(
      MonobotConfig monobotConfig, Path entryDir, JsonNode override) {
    var contribRefs = new TreeMap<String, SequencedMap<String, String>>();

    override
        .path("contrib")
        .fields()
        .forEachRemaining(
            field -> {
              var index = field.getValue().path("repository").path("index");
              if (!index.isTextual()) {
                return;
              }
              RepoConfig repoConfig;
              try {
                repoConfig =
                    objectMapper.readValue(
                        entryDir.resolve(index.asText()).toFile(), RepoConfig.class);
              } catch (IOException e) {
                throw new RuntimeException(
                    "[" + monobotConfig.label() + "]: " + index.asText() + " cannot be read", e);
              }
              var template = repoConfig.getSources().templates().getFirst();
              var refs = new LinkedHashMap<String, String>();
              repoConfig
                  .getVersions()
                  .forEach(
                      (version, context) -> {
                        var materialized =
                            template.materialize(version.version(), context.derived());
                        var ref = materialized.getOrDefault("tag", materialized.get("commit"));
                        if (ref != null) {
                          refs.put(version.version(), ref);
                        }
                      });
              contribRefs.put(field.getKey(), refs);
            });

    return contribRefs;
  }

  /// A flavor's contrib control files, every version of them, newest version last so that what a
  /// later release says about an extension is what is kept.
  private Map<String, JsonNode> contrib(Path entryDir, Versions versions) {
    var contrib = new TreeMap<String, JsonNode>();

    versions.keySet().stream()
        .sorted()
        .map(version -> read(entryDir, version, FILENAME_CONTRIB))
        .filter(document -> document != null && document.isObject())
        .forEach(
            document ->
                document
                    .fields()
                    .forEachRemaining(field -> contrib.put(field.getKey(), field.getValue())));

    return contrib;
  }

  private JsonNode read(Path entryDir, Version version, String filename) {
    return read(entryDir.resolve(DIR_METADATA).resolve(version.version()).resolve(filename));
  }

  private JsonNode read(Path file) {
    if (!Files.exists(file)) {
      return null;
    }
    try {
      return objectMapper.readTree(file.toFile());
    } catch (IOException e) {
      throw new RuntimeException(file + " cannot be read", e);
    }
  }

  /// The snapshot as committed, brought up to date first when this run is the one that writes the
  /// catalog and is allowed to ask.
  private JsonNode snapshot(
      MonobotConfig monobotConfig,
      Path entryDir,
      JsonNode override,
      JsonNode meta,
      SequencedMap<String, String> refs) {
    var directory = entryDir.resolve(DIR_METADATA);
    var committed = read(directory.resolve(FILENAME_UPSTREAM));
    // Only what monobot still reads is carried over, so a source dropped from the snapshot drops
    // out of every committed one on the next run rather than lingering as a field nothing reads.
    var snapshot = objectMapper.createObjectNode();
    if (committed != null && committed.path(KEY_FORGE).isObject()) {
      snapshot.set(KEY_FORGE, committed.get(KEY_FORGE).deepCopy());
    }

    if (mode != Mode.GENERATE || !scrapeUpstream) {
      return snapshot;
    }

    repositoryUrl(monobotConfig, override, meta)
        .flatMap(Forge::of)
        .ifPresent(forge -> scrapeForge(monobotConfig, snapshot, forge, refs));

    if (!snapshot.equals(committed)) {
      documentWriter.write(directory, FILENAME_UPSTREAM, snapshot);
    }

    return snapshot;
  }

  /// The repository the forge is asked about. The override's, then the one `monobot.json` lists
  /// tags from, then whichever META.json names, so a PGXN-hosted entry still finds its repository.
  private static Optional<String> repositoryUrl(
      MonobotConfig monobotConfig, JsonNode override, JsonNode meta) {
    var overridden = override.path("repository").path("url");
    if (overridden.isTextual()) {
      return Optional.of(overridden.asText());
    }
    if (monobotConfig.repoUrl() != null) {
      return Optional.of(monobotConfig.repoUrl().toString());
    }
    if (meta == null) {
      return Optional.empty();
    }
    var repository = meta.path("resources").path("repository");

    return Optional.ofNullable(repository.path("web").asText(repository.path("url").asText(null)));
  }

  private void scrapeForge(
      MonobotConfig monobotConfig,
      ObjectNode snapshot,
      Forge forge,
      SequencedMap<String, String> refs) {
    var described = snapshot.path(KEY_FORGE);
    var readme =
        described.path(KEY_README).isObject() && !refreshUpstream
            ? ((ObjectNode) described.get(KEY_README)).deepCopy()
            : objectMapper.createObjectNode();

    ObjectNode repository;
    if (refreshUpstream || !described.isObject()) {
      LOG.infov("[{0}]: asking {1} about itself", monobotConfig.label(), forge.webUrl());
      var answered = upstreamClient.repository(forge);
      if (answered.isEmpty()) {
        LOG.warnv("[{0}]: {1} is not a repository", monobotConfig.label(), forge.webUrl());

        return;
      }
      repository = answered.get();
    } else {
      repository = ((ObjectNode) described).deepCopy();
    }

    // The forge's own spelling of where it lives, which after a rename is not the one asked for.
    var canonical = Forge.of(repository.path("url").asText(null)).orElse(forge);
    refs.values().stream()
        .filter(ref -> ref != null && !readme.has(ref))
        .distinct()
        .forEach(ref -> readme.put(ref, upstreamClient.readme(canonical, ref).orElse(null)));

    repository.set(KEY_README, readme);
    snapshot.set(KEY_FORGE, repository);
  }
}
