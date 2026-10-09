package dev.monogres.monobot.about;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.MissingNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.SequencedMap;
import java.util.function.Supplier;
import java.util.stream.Stream;
import java.util.stream.StreamSupport;

/// What one entry is, for a reader rather than for the build: `about.json`.
///
/// A function of what is committed and nothing else. Every input is a file in the catalog -- the
/// override in `monobot.json`, the newest version's `control.json` and `META.json`, and the
/// snapshot of what the forge said in `metadata/upstream.json` -- so `check` derives the same
/// document `generate` did without asking the network anything.
///
/// Each field is taken from the first source that says something about it. The order is per field,
/// because each source is good at different things:
///
/// | field              | first to last                                                        |
/// |--------------------|----------------------------------------------------------------------|
/// | `description`      | override, control `comment`, META `abstract`, forge About            |
/// | `long_description` | override, forge About, META `description`, META `abstract`          |
/// | `homepage`         | override, forge homepage, META homepage, repository                  |
/// | `license`          | override, forge (detected from the file), META                       |
/// | `maintainers`      | override, META `maintainer`                                          |
/// | `keywords`         | override, META `tags` and forge topics together                      |
/// | `categories`       | override                                                             |
/// | `repository.url`   | override, forge (canonical, after redirects), `monobot.json` url     |
///
/// The control comment is preferred for the short description because it is what `\dx` shows: it
/// is the extension describing itself, one line long. The forge's About is preferred for the long
/// one because it is the project describing itself, which is what the catalog page is for.
public final class AboutResolver {
  private AboutResolver() {}

  /// Everything the document is derived from. Absent inputs are [MissingNode]s rather than nulls,
  /// so a path into one is a path into nothing rather than an exception.
  public record Inputs(
      JsonNode override,
      JsonNode control,
      JsonNode meta,
      JsonNode upstream,
      String repoUrl,
      SequencedMap<String, String> refs,
      Map<String, JsonNode> contrib,
      Map<String, SequencedMap<String, String>> contribRefs) {
    public Inputs {
      override = orMissing(override);
      control = orMissing(control);
      meta = orMissing(meta);
      upstream = orMissing(upstream);
      refs = refs == null ? new LinkedHashMap<>() : refs;
      contrib = contrib == null ? Map.of() : contrib;
      contribRefs = contribRefs == null ? Map.of() : contribRefs;
    }

    /// An entry with no contrib extension built from a repository of its own.
    public Inputs(
        JsonNode override,
        JsonNode control,
        JsonNode meta,
        JsonNode upstream,
        String repoUrl,
        SequencedMap<String, String> refs,
        Map<String, JsonNode> contrib) {
      this(override, control, meta, upstream, repoUrl, refs, contrib, null);
    }
  }

  private static JsonNode orMissing(JsonNode node) {
    return node == null || node.isNull() ? MissingNode.getInstance() : node;
  }

  public static ObjectNode resolve(ObjectMapper objectMapper, Inputs inputs) {
    var override = inputs.override();
    var forge = inputs.upstream().path("forge");
    var meta = inputs.meta();
    var about = objectMapper.createObjectNode();

    putFirst(
        about,
        "description",
        text(override, "description"),
        text(inputs.control(), "comment"),
        text(meta, "abstract"),
        text(forge, "description"));
    putFirst(
        about,
        "long_description",
        text(override, "long_description"),
        text(forge, "description"),
        text(meta, "description"),
        text(meta, "abstract"));
    final var repositoryUrl =
        first(
            text(override.path("repository"), "url"),
            text(forge, "url"),
            () -> Optional.ofNullable(inputs.repoUrl()).filter(url -> !url.isBlank()));
    // Most projects have no website of their own and their repository is where a reader goes, so
    // that is the homepage when nothing names another.
    putFirst(
        about,
        "homepage",
        text(override, "homepage"),
        text(forge, "homepage"),
        text(meta.path("resources"), "homepage"),
        () -> repositoryUrl);
    putFirst(
        about,
        "license",
        () -> text(override, "license").get(),
        () -> Licenses.of(forge.path("license").asText(null)),
        () -> Licenses.ofPgxn(meta.path("license")));

    var maintainers =
        override.has("maintainers")
            ? strings(override.get("maintainers"))
            : strings(meta.path("maintainer"));
    if (!maintainers.isEmpty()) {
      about.set("maintainers", array(objectMapper, maintainers));
    }

    var keywords =
        override.has("keywords")
            ? strings(override.get("keywords"))
            : keywords(strings(meta.path("tags")), strings(forge.path("topics")));
    if (!keywords.isEmpty()) {
      about.set("keywords", array(objectMapper, keywords));
    }

    var categories = strings(override.path("categories"));
    if (!categories.isEmpty()) {
      about.set("categories", array(objectMapper, categories));
    }

    repositoryUrl.ifPresent(url -> about.putObject("repository").put("url", url));

    var versions = objectMapper.createObjectNode();
    inputs
        .refs()
        .forEach(
            (version, ref) -> {
              var entry = versions.putObject(version);
              if (ref == null) {
                return;
              }
              entry.put("ref", ref);
              var readme = forge.path("readme").path(ref);
              repositoryUrl
                  .flatMap(Forge::of)
                  .filter(found -> readme.isTextual())
                  .ifPresent(found -> entry.put("readme", found.rawUrl(ref, readme.asText())));
            });
    if (!versions.isEmpty()) {
      about.set("versions", versions);
    }

    var contrib = contrib(objectMapper, inputs, about);
    if (!contrib.isEmpty()) {
      about.set("contrib", contrib);
    }

    return about;
  }

  /// The extensions a flavor carries in its own tree, each described the way an external one is,
  /// from its control file and the override's `contrib` block. What they
  /// share with the flavor -- the repository, the refs, the licence -- is the flavor's and is not
  /// repeated.
  private static ObjectNode contrib(ObjectMapper objectMapper, Inputs inputs, ObjectNode flavor) {
    var names = new LinkedHashSet<String>(inputs.contrib().keySet());
    inputs.override().path("contrib").fieldNames().forEachRemaining(names::add);

    var contrib = objectMapper.createObjectNode();
    names.stream()
        .sorted()
        .forEach(
            name -> {
              var override = inputs.override().path("contrib").path(name);
              var control = inputs.contrib().getOrDefault(name, MissingNode.getInstance());
              var about = objectMapper.createObjectNode();

              putFirst(
                  about, "description", text(override, "description"), text(control, "comment"));
              putFirst(
                  about,
                  "long_description",
                  text(override, "long_description"),
                  text(control, "comment"));
              putFirst(about, "homepage", text(override, "homepage"));
              putFirst(about, "license", text(override, "license"), text(flavor, "license"));
              var categories = strings(override.path("categories"));
              if (!categories.isEmpty()) {
                about.set("categories", array(objectMapper, categories));
              }
              if (override.path("repository").has("url")) {
                about
                    .putObject("repository")
                    .put("url", override.path("repository").path("url").asText());
              }
              // An extension built from a repository of its own names its ref there per flavor
              // version; the flavor's refs point into the wrong tree.
              var refs = inputs.contribRefs().get(name);
              if (refs != null && !refs.isEmpty()) {
                var versions = about.putObject("versions");
                refs.forEach((version, ref) -> versions.putObject(version).put("ref", ref));
              }

              if (!about.isEmpty()) {
                contrib.set(name, about);
              }
            });

    return contrib;
  }

  private static Supplier<Optional<String>> text(JsonNode node, String field) {
    return () -> {
      var value = node.path(field);
      if (!value.isTextual()) {
        return Optional.empty();
      }
      var text = value.asText().strip();

      return text.isEmpty() ? Optional.empty() : Optional.of(text);
    };
  }

  @SafeVarargs
  private static Optional<String> first(Supplier<Optional<String>>... candidates) {
    return Stream.of(candidates).map(Supplier::get).flatMap(Optional::stream).findFirst();
  }

  @SafeVarargs
  private static void putFirst(
      ObjectNode into, String field, Supplier<Optional<String>>... candidates) {
    first(candidates).ifPresent(value -> into.put(field, value));
  }

  /// A string or a list of them, as a list. PGXN allows a maintainer to be either.
  private static List<String> strings(JsonNode node) {
    if (node.isTextual()) {
      return node.asText().isBlank() ? List.of() : List.of(node.asText().strip());
    }
    if (!node.isArray()) {
      return List.of();
    }

    return Stream.of(node)
        .flatMap(array -> StreamSupport.stream(array.spliterator(), false))
        .filter(JsonNode::isTextual)
        .map(element -> element.asText().strip())
        .filter(element -> !element.isEmpty())
        .toList();
  }

  /// META's tags and the forge's topics together, first spelling kept. Compared lowercased and with
  /// `-` and `_` read as spaces, since a topic is lowercase and hyphenated by rule and a tag is
  /// neither: `nearest-neighbor-search` is the tag `nearest neighbor search`, and `PostGIS` is a
  /// better keyword than `postgis`.
  private static List<String> keywords(List<String> tags, List<String> topics) {
    var seen = new LinkedHashMap<String, String>();
    Stream.concat(tags.stream(), topics.stream())
        .filter(Objects::nonNull)
        .forEach(
            keyword ->
                seen.putIfAbsent(
                    keyword.toLowerCase(Locale.ROOT).replaceAll("[-_\\s]+", " "), keyword));

    return List.copyOf(seen.values());
  }

  private static ArrayNode array(ObjectMapper objectMapper, List<String> values) {
    var array = objectMapper.createArrayNode();
    values.forEach(array::add);

    return array;
  }
}
