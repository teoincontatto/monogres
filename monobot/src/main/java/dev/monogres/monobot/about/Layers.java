package dev.monogres.monobot.about;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.monogres.monobot.config.output.Version;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.SequencedMap;
import java.util.stream.StreamSupport;

/// One document per version, stored once.
///
/// Everything an entry says about itself is versioned -- `about.json`, the forge snapshot in
/// `metadata/upstream.json`, and the `about` override in `monobot.json` -- and most of it is the
/// same from one release to the next. So each is written as the newest version in full, and every
/// older one as only what differs from the version after it:
///
/// ```json
/// {
///   "latest": {"version": "5.4", "description": "...", "ref": "BABEL_5_4_0__PG_17_7"},
///   "versions": {
///     "5.3": {"ref": "BABEL_5_3_0__PG_17_6"},
///     "5.2": {"ref": "BABEL_5_2_0__PG_17_5"}
///   }
/// }
/// ```
///
/// `latest` is what a reader most often wants, so it is the one read without applying anything.
/// The older versions are listed newest first, which is the order they are applied in: each is an
/// RFC 7386 JSON Merge Patch over the version above it, already resolved. Objects merge field by
/// field, anything else replaces, and `null` removes what the newer version had. A version that
/// differs in nothing is `{}`, and is still listed, because being listed is what says the version
/// is there.
///
/// The override in `monobot.json` has the same shape, except that its `latest` names no version:
/// it is whatever the newest catalogued version is. An override's patch applies to the version it
/// is keyed on and every older one, whether or not that exact version is catalogued, so a
/// correction for "1.4 and before" is written once, under `1.4`.
public final class Layers {
  public static final String LATEST = "latest";
  public static final String VERSIONS = "versions";
  public static final String VERSION = "version";

  private Layers() {}

  /// `patch` merged over `target`, per RFC 7386. Neither argument is modified.
  public static JsonNode apply(JsonNode target, JsonNode patch) {
    if (!patch.isObject()) {
      return patch.deepCopy();
    }
    var merged =
        target != null && target.isObject()
            ? ((ObjectNode) target).deepCopy()
            : JsonNodeFactory.instance.objectNode();
    patch
        .properties()
        .forEach(
            field -> {
              if (field.getValue().isNull()) {
                merged.remove(field.getKey());
              } else {
                merged.set(field.getKey(), apply(merged.get(field.getKey()), field.getValue()));
              }
            });

    return merged;
  }

  /// The merge patch that turns `from` into `to`: the inverse of [#apply] for two objects. Arrays
  /// and scalars are replaced whole, which is all a merge patch can say about them.
  public static ObjectNode diff(JsonNode from, JsonNode to) {
    var patch = JsonNodeFactory.instance.objectNode();
    from.properties()
        .forEach(
            field -> {
              if (!to.has(field.getKey())) {
                patch.putNull(field.getKey());
              }
            });
    to.properties()
        .forEach(
            field -> {
              var before = from.get(field.getKey());
              var after = field.getValue();
              if (after.equals(before)) {
                return;
              }
              if (after.isObject() && before != null && before.isObject()) {
                patch.set(field.getKey(), diff(before, after));
              } else {
                patch.set(field.getKey(), after.deepCopy());
              }
            });

    return patch;
  }

  /// Every version a layered document holds, fully resolved, newest first. A document that is not
  /// layered holds none.
  public static SequencedMap<String, ObjectNode> resolve(JsonNode layered) {
    var resolved = new LinkedHashMap<String, ObjectNode>();
    var latest = layered.path(LATEST);
    if (!latest.isObject() || !latest.path(VERSION).isTextual()) {
      return resolved;
    }

    var current = ((ObjectNode) latest).deepCopy();
    current.remove(VERSION);
    resolved.put(latest.get(VERSION).asText(), current);
    for (var field : layered.path(VERSIONS).properties()) {
      current = (ObjectNode) apply(current, field.getValue());
      resolved.put(field.getKey(), current);
    }

    return resolved;
  }

  /// The layered document holding `documents`, which are given newest first. The inverse of
  /// [#resolve].
  public static ObjectNode layer(
      ObjectMapper objectMapper, SequencedMap<String, ? extends JsonNode> documents) {
    var layered = objectMapper.createObjectNode();
    if (documents.isEmpty()) {
      return layered;
    }

    var newest = documents.firstEntry();
    var latest = layered.putObject(LATEST);
    latest.put(VERSION, newest.getKey());
    latest.setAll((ObjectNode) newest.getValue().deepCopy());

    JsonNode after = newest.getValue();
    var versions = objectMapper.createObjectNode();
    for (var entry : documents.sequencedEntrySet()) {
      if (entry.getKey().equals(newest.getKey())) {
        continue;
      }
      versions.set(entry.getKey(), diff(after, entry.getValue()));
      after = entry.getValue();
    }
    if (!versions.isEmpty()) {
      layered.set(VERSIONS, versions);
    }

    return layered;
  }

  /// The override in force at each of `versions`, which are given newest first: the override's
  /// `latest`, with every patch keyed on a version at or above that one applied, newest first.
  public static SequencedMap<String, JsonNode> override(JsonNode override, List<Version> versions) {
    var patches =
        StreamSupport.stream(override.path(VERSIONS).properties().spliterator(), false)
            .sorted(
                Comparator.comparing(
                        (Map.Entry<String, JsonNode> field) -> new Version(field.getKey()))
                    .reversed())
            .toList();

    var resolved = new LinkedHashMap<String, JsonNode>();
    JsonNode current = override.path(LATEST).isObject() ? override.get(LATEST) : null;
    var next = 0;
    for (var version : versions) {
      while (next < patches.size()
          && new Version(patches.get(next).getKey()).compareTo(version) >= 0) {
        current = apply(current, patches.get(next++).getValue());
      }
      resolved.put(version.version(), current);
    }

    return resolved;
  }
}
