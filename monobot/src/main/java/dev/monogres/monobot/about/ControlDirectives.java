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
import java.util.regex.Pattern;
import java.util.stream.StreamSupport;

/// The control file of one version as `about.json` reports it: the directives a reader can act
/// on, with whatever the build would have filled in written by hand.
///
/// Only the directives Postgres documents are kept, in the order its documentation lists them,
/// and `comment` is not one of them: it is purely informative and is already the `description`.
/// Anything else the file declared -- a directive newer than this list, or a line a build
/// substitutes away, such as pglogical's `__REQUIRES__` -- is left out.
///
/// An extension whose build writes its control file ships a template, and `control.json` keeps
/// the template's placeholders as the archive spelled them (`@CARGO_VERSION@`,
/// `${PROJECT_VERSION}`). They are not values, so `monobot.json` replaces them in its `control`
/// block: a merge patch over the directives of one version, keyed by the release version the
/// archive was catalogued under, and applied to that version alone. A newer version therefore
/// inherits no correction, and its own placeholder is caught: a placeholder nothing replaced is an
/// error naming the directive, since leaving it in would publish it, and leaving the directive out
/// would hide that it is missing.
public final class ControlDirectives {
  public static final String KEY = "control";

  /// Every directive kept, with the one JSON type its value has. A control file has no numbers:
  /// a version is a string however it is spelled.
  static final SequencedMap<String, JsonNodeType> TYPES = types();

  // `@NAME@` (autoconf, CMake configure_file, pgrx), `${NAME}` (CMake) and `__NAME__` (sed).
  private static final Pattern PLACEHOLDER =
      Pattern.compile("@[A-Za-z_][A-Za-z0-9_]*@|\\$\\{[A-Za-z_][A-Za-z0-9_]*}|__[A-Z][A-Z0-9_]*__");

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

  /// The directives of `control` with `override` applied, or an empty object where there is no
  /// control file and no override.
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
                    "control." + name + " is not a control directive monobot reports");
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
          "control."
              + name
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
                  "control."
                      + name
                      + " is the build placeholder \""
                      + text
                      + "\": write the value the build fills in under control.<version> in"
                      + " monobot.json");
            });
  }

  private static String describe(JsonNodeType type) {
    return type.name().toLowerCase(Locale.ROOT);
  }
}
