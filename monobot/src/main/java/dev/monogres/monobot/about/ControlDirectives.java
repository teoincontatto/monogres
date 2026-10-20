package dev.monogres.monobot.about;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.JsonNodeType;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.SequencedMap;
import java.util.TreeSet;
import java.util.regex.Pattern;
import java.util.stream.StreamSupport;

/// The control files of one version as `about.json` reports them, keyed by the extension each
/// declares: the directives a reader can act on, with whatever the build would have filled in
/// written by hand.
///
/// Only the directives Postgres documents are kept, in the order its documentation lists them,
/// and `comment` is not one of them: it is purely informative and is already the `description`.
/// Anything else the file declared -- a directive newer than this list, or a line a build
/// substitutes away, such as pglogical's `__REQUIRES__` -- is left out.
///
/// An extension whose build writes its control file ships a template, and `control.json` keeps
/// the template's placeholders as the archive spelled them (`@CARGO_VERSION@`,
/// `${PROJECT_VERSION}`). They are not values, so `monobot.json` replaces them in its `control`
/// block: a merge patch over the control files of one version, keyed by the release version the
/// archive was catalogued under and then by extension, and applied to that version alone. `null`
/// for an extension removes it, for one the archive declares and the build does not install. A
// newer version therefore
/// inherits no correction, and its own placeholder is caught: a placeholder nothing replaced is an
/// error naming the directive, since leaving it in would publish it, and leaving the directive out
/// would hide that it is missing.
public final class ControlDirectives {
  public static final String KEY = "control";

  /// Every directive kept, with the one JSON type its value has. A control file has no numbers:
  /// a version is a string however it is spelled.
  static final SequencedMap<String, JsonNodeType> TYPES = types();

  // `@NAME@` (autoconf, CMake configure_file, pgrx), `${NAME}` (CMake), `__NAME__` and `{{NAME}}`
  // (sed, templating), and a bare `NAME` that is the whole value or the last part of a path, which
  // sed substitutes as readily (pg_tle's `EXTVERSION` and `$libdir/EXTNAME`, pg_repack's
  // `REPACK_VERSION`). No directive's real value is an upper-case word: versions are digits, and
  // schemas and library names are lower case.
  private static final Pattern PLACEHOLDER =
      Pattern.compile(
          "@[A-Za-z_][A-Za-z0-9_]*@"
              + "|\\$\\{[A-Za-z_][A-Za-z0-9_]*}"
              + "|__[A-Z][A-Z0-9_]*__"
              + "|\\{\\{\\s*[A-Za-z_][A-Za-z0-9_]*\\s*}}"
              + "|(?:^|/)[A-Z][A-Z0-9_]{2,}$");

  private ControlDirectives() {}

  private static SequencedMap<String, JsonNodeType> types() {
    var types = new LinkedHashMap<String, JsonNodeType>();
    types.put("directory", JsonNodeType.STRING);
    types.put("default_version", JsonNodeType.STRING);
    types.put("encoding", JsonNodeType.STRING);
    types.put("module_pathname", JsonNodeType.STRING);
    types.put("requires", JsonNodeType.ARRAY);
    types.put("no_relocate", JsonNodeType.ARRAY);
    types.put("superuser", JsonNodeType.BOOLEAN);
    types.put("trusted", JsonNodeType.BOOLEAN);
    types.put("relocatable", JsonNodeType.BOOLEAN);
    types.put("schema", JsonNodeType.STRING);

    return Collections.unmodifiableSequencedMap(types);
  }

  /// Every control file of `controls`, `{extension: directives}`, with `correction` applied:
  /// `{extension: merge patch}`, where `null` removes the extension. Ordered by extension.
  ///
  /// @throws IllegalArgumentException as [#resolve] does, naming the extension, and when the
  ///     correction patches an extension `controls` does not declare.
  public static ObjectNode resolveAll(
      ObjectMapper objectMapper, JsonNode controls, JsonNode correction) {
    var names = new TreeSet<String>();
    controls.fieldNames().forEachRemaining(names::add);
    correction
        .properties()
        .forEach(
            field -> {
              if (!names.contains(field.getKey())) {
                throw new IllegalArgumentException(
                    KEY
                        + "."
                        + field.getKey()
                        + " corrects an extension the archive declares no control file for");
              }
            });

    var resolved = objectMapper.createObjectNode();
    for (var name : names) {
      var patch = correction.path(name);
      if (patch.isNull()) {
        continue;
      }
      try {
        var directives = resolve(objectMapper, controls.get(name), patch);
        if (!directives.isEmpty()) {
          resolved.set(name, directives);
        }
      } catch (IllegalArgumentException e) {
        throw new IllegalArgumentException(KEY + "." + name + "." + e.getMessage(), e);
      }
    }

    return resolved;
  }

  /// The directives of one control file with `override` applied, or an empty object where there
  /// is no control file and no override. An error names the directive, not the extension.
  ///
  /// @throws IllegalArgumentException when the override names a directive that is not one, a
  ///     directive has a value of the wrong type, or a placeholder is left unreplaced.
  public static ObjectNode resolve(ObjectMapper objectMapper, JsonNode control, JsonNode override) {
    var directives = objectMapper.createObjectNode();
    TYPES.keySet().stream()
        .filter(name -> control.has(name) && !control.get(name).isNull())
        .forEach(name -> directives.set(name, control.get(name).deepCopy()));

    var patched = override.isObject() ? patch(directives, override) : directives;

    // Laid out in the documented order whatever order the file or the override used, so a
    // reordered control file is not a diff.
    var ordered = objectMapper.createObjectNode();
    TYPES.forEach(
        (name, type) -> {
          var value = patched.get(name);
          if (value != null) {
            check(name, type, value);
            ordered.set(name, value);
          }
        });

    return ordered;
  }

  private static ObjectNode patch(ObjectNode directives, JsonNode override) {
    override
        .fieldNames()
        .forEachRemaining(
            name -> {
              if (!TYPES.containsKey(name)) {
                throw new IllegalArgumentException(
                    name + " is not a control directive monobot reports");
              }
            });

    return (ObjectNode) Layers.apply(directives, override);
  }

  private static void check(String name, JsonNodeType type, JsonNode value) {
    var elements =
        value.isArray()
            ? StreamSupport.stream(value.spliterator(), false).toList()
            : List.of(value);
    var elementType = type == JsonNodeType.ARRAY ? JsonNodeType.STRING : type;
    if (value.getNodeType() != type
        || elements.stream().anyMatch(element -> element.getNodeType() != elementType)) {
      throw new IllegalArgumentException(
          name
              + " is "
              + value
              + ", and it must be "
              + (type == JsonNodeType.ARRAY ? "an array of strings" : "a " + describe(type)));
    }
    elements.stream()
        .map(JsonNode::asText)
        .filter(text -> PLACEHOLDER.matcher(text).find())
        .findFirst()
        .ifPresent(
            text -> {
              throw new IllegalArgumentException(
                  name
                      + " is the build placeholder \""
                      + text
                      + "\": write the value the build fills in under"
                      + " control.<version>.<extension> in monobot.json, or null the extension if"
                      + " the build does not install it");
            });
  }

  private static String describe(JsonNodeType type) {
    return type.name().toLowerCase(Locale.ROOT);
  }
}
