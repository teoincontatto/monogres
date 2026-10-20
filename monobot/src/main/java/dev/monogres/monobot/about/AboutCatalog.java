package dev.monogres.monobot.about;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.MissingNode;
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
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.SequencedMap;
import java.util.TreeMap;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/// The two halves of what an entry says about itself to a reader: a snapshot of what its upstream
/// says, and the `about.json` derived from it. Both are versioned, and stored by [Layers] as the
/// newest version in full and every older one as what differs from the version after it.
///
/// They are kept apart on purpose. The snapshot, `metadata/upstream.json`, is the only part that
/// comes off the network, and it is committed: what the forge answered is then a reviewable diff
/// rather than something a run happened to see, and `check` re-derives `about.json` from it without
/// a request. A forge only ever answers about the repository as it is today, so each version keeps
/// the answer from when it was first catalogued: a version is asked about once, when it has no
/// snapshot, and `refreshUpstream` asks again about the newest version only.
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

  /// The document for one entry, or empty when nothing describes it: an entry whose newest version
  /// has no description and no repository has nothing a reader could use, and writing one anyway
  /// would add a file to every fixture that never asked for it.
  public Optional<ObjectNode> about(MonobotConfig monobotConfig, Path entryDir, Versions versions) {
    var newestFirst = versions.keySet().stream().sorted(Comparator.reverseOrder()).toList();
    if (newestFirst.isEmpty()) {
      return Optional.empty();
    }
    var overrides = Layers.override(monobotConfig.about(), newestFirst);
    var controlOverrides = controlOverrides(monobotConfig, newestFirst);
    var refs = refs(monobotConfig, versions, overrides);
    var metas = new LinkedHashMap<String, JsonNode>();
    newestFirst.forEach(
        version -> metas.put(version.version(), read(entryDir, version, FILENAME_META)));

    var upstream = snapshot(monobotConfig, entryDir, newestFirst, overrides, metas, refs);
    var contribRefs = contribRefs(monobotConfig, entryDir, overrides.firstEntry().getValue());
    var repoUrl = monobotConfig.repoUrl() == null ? null : monobotConfig.repoUrl().toString();

    var documents = new LinkedHashMap<String, ObjectNode>();
    for (var version : newestFirst) {
      var key = version.version();
      var contribRef = new TreeMap<String, String>();
      contribRefs.forEach(
          (name, byVersion) -> {
            if (byVersion.containsKey(key)) {
              contribRef.put(name, byVersion.get(key));
            }
          });
      ObjectNode document;
      try {
        document =
            AboutResolver.resolve(
                objectMapper,
                new AboutResolver.Inputs(
                    overrides.get(key),
                    read(entryDir, version, FILENAME_CONTROL),
                    metas.get(key),
                    upstream.get(key),
                    repoUrl,
                    refs.get(key),
                    contrib(entryDir, version),
                    contribRef,
                    controlOverrides.get(key)));
      } catch (IllegalArgumentException e) {
        throw new IllegalArgumentException(
            "[" + monobotConfig.label() + "] " + key + ": " + e.getMessage(), e);
      }
      documents.put(key, document);
    }

    var newest = documents.firstEntry().getValue();
    if (!newest.has("description") && !newest.has("repository")) {
      return Optional.empty();
    }

    return Optional.of(Layers.layer(objectMapper, documents));
  }

  /// The `control` corrections of `monobot.json`, by version. A key naming no catalogued version
  /// is an error rather than a correction that silently applies to nothing: it is most likely a
  /// version spelled the way the control file spells it rather than the way `versions` does.
  private static Map<String, JsonNode> controlOverrides(
      MonobotConfig monobotConfig, List<Version> versions) {
    var catalogued = versions.stream().map(Version::version).toList();
    var overrides = new HashMap<String, JsonNode>();
    monobotConfig
        .control()
        .properties()
        .forEach(
            field -> {
              if (!catalogued.contains(field.getKey())) {
                throw new IllegalArgumentException(
                    "["
                        + monobotConfig.label()
                        + "] control."
                        + field.getKey()
                        + " corrects a version that is not catalogued, which are "
                        + String.join(", ", catalogued));
              }
              overrides.put(field.getKey(), field.getValue());
            });

    return overrides;
  }

  /// The ref each version's archive was cut from, or null where it names none.
  ///
  /// Spelled by the override's `repository.ref` template where there is one, which is how an entry
  /// whose archives come from somewhere other than its repository (postgis) names its tags.
  /// Otherwise it is the `tag` or the `commit` the source materializes to, which is what every
  /// forge-hosted entry already has, and a version with neither has no ref.
  private Map<String, String> refs(
      MonobotConfig monobotConfig, Versions versions, Map<String, JsonNode> overrides) {
    var template = monobotConfig.sources().templates().getFirst();
    var refs = new HashMap<String, String>();

    versions.forEach(
        (version, context) -> {
          var materialized = template.materialize(version.version(), context.derived());
          var refTemplate =
              orMissing(overrides.get(version.version())).path("repository").path("ref");
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

  private static JsonNode orMissing(JsonNode node) {
    return node == null ? MissingNode.getInstance() : node;
  }

  /// The refs of the contrib extensions a flavor builds out of a repository of its own, by flavor
  /// version. The override names that repository's download index beside the entry
  /// (`"repository": {"url": ..., "index": "ext.json"}`), which is what the build fetches those
  /// sources from, so the ref each flavor version builds is read rather than written twice.
  private Map<String, Map<String, String>> contribRefs(
      MonobotConfig monobotConfig, Path entryDir, JsonNode override) {
    var contribRefs = new TreeMap<String, Map<String, String>>();

    orMissing(override)
        .path("contrib")
        .properties()
        .forEach(
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
              var refs = new HashMap<String, String>();
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

  /// The contrib control files of one version of a flavor, by extension name.
  private Map<String, JsonNode> contrib(Path entryDir, Version version) {
    var contrib = new TreeMap<String, JsonNode>();
    var document = read(entryDir, version, FILENAME_CONTRIB);
    if (document != null && document.isObject()) {
      document.properties().forEach(field -> contrib.put(field.getKey(), field.getValue()));
    }

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

  /// The snapshot of each version as committed, newest first, with the versions that have none
  /// asked about first when this run is the one that writes the catalog and is allowed to ask. A
  /// version with no snapshot and no permission to take one maps to null.
  private SequencedMap<String, JsonNode> snapshot(
      MonobotConfig monobotConfig,
      Path entryDir,
      List<Version> newestFirst,
      Map<String, JsonNode> overrides,
      Map<String, JsonNode> metas,
      Map<String, String> refs) {
    var directory = entryDir.resolve(DIR_METADATA);
    var committed = read(directory.resolve(FILENAME_UPSTREAM));
    var resolved = committed == null ? Map.<String, ObjectNode>of() : Layers.resolve(committed);

    // Only the versions still catalogued, and only what monobot still reads of each, are carried
    // over, so neither lingers in the committed snapshot once nothing reads it.
    var snapshot = new LinkedHashMap<String, JsonNode>();
    newestFirst.forEach(
        version -> {
          var kept = resolved.get(version.version());
          ObjectNode carried = null;
          if (kept != null) {
            carried = objectMapper.createObjectNode();
            if (kept.path(KEY_FORGE).isObject()) {
              carried.set(KEY_FORGE, kept.get(KEY_FORGE).deepCopy());
            }
          }
          snapshot.put(version.version(), carried);
        });

    if (mode != Mode.GENERATE || !scrapeUpstream) {
      return snapshot;
    }

    var answers = new HashMap<Forge, Optional<ObjectNode>>();
    var newest = newestFirst.getFirst().version();
    snapshot.replaceAll(
        (version, carried) -> {
          if (carried != null && !(refreshUpstream && version.equals(newest))) {
            return carried;
          }
          var asked = objectMapper.createObjectNode();
          repositoryUrl(monobotConfig, orMissing(overrides.get(version)), metas.get(version))
              .flatMap(Forge::of)
              .flatMap(forge -> scrapeForge(monobotConfig, answers, forge, refs.get(version)))
              .ifPresent(forge -> asked.set(KEY_FORGE, forge));

          return asked;
        });

    // Compared as printed, so a snapshot laid out or ordered other than the way the catalog prints
    // it is rewritten too.
    var layered = Layers.layer(objectMapper, snapshot);
    if (committed == null || !documentWriter.render(layered).equals(readString(directory))) {
      documentWriter.write(directory, FILENAME_UPSTREAM, layered);
    }

    return snapshot;
  }

  private static String readString(Path directory) {
    try {
      return Files.readString(directory.resolve(FILENAME_UPSTREAM));
    } catch (IOException e) {
      throw new RuntimeException(directory.resolve(FILENAME_UPSTREAM) + " cannot be read", e);
    }
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

  /// What the forge says about one version: the repository as it is today, asked once per run
  /// however many versions want it, and the README at the version's ref. A field the forge leaves
  /// null is left out, since a `null` in a layered document means the field was removed.
  private Optional<ObjectNode> scrapeForge(
      MonobotConfig monobotConfig,
      Map<Forge, Optional<ObjectNode>> answers,
      Forge forge,
      String ref) {
    var answered =
        answers.computeIfAbsent(
            forge,
            asked -> {
              LOG.infov("[{0}]: asking {1} about itself", monobotConfig.label(), asked.webUrl());
              var repository = upstreamClient.repository(asked);
              if (repository.isEmpty()) {
                LOG.warnv("[{0}]: {1} is not a repository", monobotConfig.label(), asked.webUrl());
              }

              return repository;
            });
    if (answered.isEmpty()) {
      return Optional.empty();
    }

    var repository = answered.get().deepCopy();
    repository.properties().removeIf(field -> field.getValue().isNull());
    // The forge's own spelling of where it lives, which after a rename is not the one asked for.
    var canonical = Forge.of(repository.path("url").asText(null)).orElse(forge);
    if (ref != null) {
      upstreamClient.readme(canonical, ref).ifPresent(path -> repository.put(KEY_README, path));
    }

    return Optional.of(repository);
  }
}
