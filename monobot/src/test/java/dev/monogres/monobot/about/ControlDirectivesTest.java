package dev.monogres.monobot.about;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.MissingNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

/// `about.json` reports the control file as the documented directives, typed, with the build's
/// placeholders replaced by hand and `comment` left to the description.
class ControlDirectivesTest {
  private final ObjectMapper objectMapper = new ObjectMapper();

  private JsonNode json(String text) {
    try {
      return objectMapper.readTree(text);
    } catch (Exception e) {
      throw new AssertionError(e);
    }
  }

  private ObjectNode resolve(String control, String override) {
    return ControlDirectives.resolve(
        objectMapper,
        control == null ? MissingNode.getInstance() : json(control),
        override == null ? MissingNode.getInstance() : json(override));
  }

  @Test
  void keepsTheDocumentedDirectivesInTheirOrderWithoutTheComment() {
    var control =
        resolve(
            """
            {
              "relocatable": false,
              "comment": "PostgreSQL Logical Replication",
              "schema": "pglogical",
              "default_version": "2.4.8",
              "superuser": true,
              "trusted": false,
              "requires": ["plpgsql"]
            }
            """,
            null);

    assertEquals(
        json(
            """
            {
              "default_version": "2.4.8",
              "requires": ["plpgsql"],
              "superuser": true,
              "trusted": false,
              "relocatable": false,
              "schema": "pglogical"
            }
            """),
        control);
    var names = new ArrayList<String>();
    control.fieldNames().forEachRemaining(names::add);
    assertEquals(
        List.of("default_version", "requires", "superuser", "trusted", "relocatable", "schema"),
        names);
  }

  @Test
  void leavesOutWhatIsNotDirective() {
    var control = resolve("{\"default_version\": \"1.0\", \"__REQUIRES__\": \"\"}", null);

    assertEquals(json("{\"default_version\": \"1.0\"}"), control);
  }

  @Test
  void theOverrideReplacesAddsAndRemovesDirectives() {
    var control =
        resolve(
            """
            {
              "default_version": "__PGLOGICAL_VERSION__",
              "module_pathname": "$libdir/pglogical",
              "__REQUIRES__": ""
            }
            """,
            """
            {
              "default_version": "2.4.8",
              "requires": ["pglogical_origin"],
              "module_pathname": null
            }
            """);

    assertEquals(
        json("{\"default_version\": \"2.4.8\", \"requires\": [\"pglogical_origin\"]}"), control);
  }

  @Test
  void placeholderLeftInIsAnError() {
    for (var placeholder :
        List.of(
            "@CARGO_VERSION@",
            "${MAJOR_VERSION}.${MINOR_VERSION}",
            "__PGLOGICAL_VERSION__",
            "$libdir/timescaledb-@PROJECT_VERSION_MOD@")) {
      var error =
          assertThrows(
              IllegalArgumentException.class,
              () -> resolve("{\"default_version\": \"" + placeholder + "\"}", null));

      assertTrue(error.getMessage().startsWith("default_version"), error.getMessage());
      assertTrue(error.getMessage().contains(placeholder), error.getMessage());
    }
  }

  @Test
  void libdirIsNotPlaceholder() {
    var control = resolve("{\"module_pathname\": \"$libdir/vector\"}", null);

    assertEquals(json("{\"module_pathname\": \"$libdir/vector\"}"), control);
  }

  @Test
  void valueOfTheWrongTypeIsAnError() {
    assertThrows(IllegalArgumentException.class, () -> resolve("{\"default_version\": 1.4}", null));
    assertThrows(IllegalArgumentException.class, () -> resolve("{}", "{\"trusted\": \"true\"}"));
    assertThrows(
        IllegalArgumentException.class, () -> resolve("{}", "{\"requires\": \"plpgsql\"}"));
    assertThrows(IllegalArgumentException.class, () -> resolve("{}", "{\"requires\": [1]}"));
  }

  @Test
  void overrideNamingNoDirectiveIsAnError() {
    var error =
        assertThrows(
            IllegalArgumentException.class, () -> resolve("{}", "{\"comment\": \"something\"}"));

    assertTrue(error.getMessage().startsWith("comment"), error.getMessage());
  }

  @Test
  void noControlFileIsNoDirectives() {
    assertTrue(resolve(null, null).isEmpty());
  }

  /// Every control file of a version is reported under its extension. A correction is keyed the
  /// same way, `null` drops an extension the build does not install, and one naming an extension
  /// the archive does not declare is an error.
  @Test
  void resolveAllKeysEveryControlFileByItsExtension() {
    var controls =
        json(
            """
            {"postgis": {"default_version": "@EXTVERSION@", "comment": "PostGIS"},
             "postgis_sfcgal": {"default_version": "@EXTVERSION@"},
             "postgis_raster": {"default_version": "@EXTVERSION@"}}
            """);
    var correction =
        json(
            """
            {"postgis": {"default_version": "3.5.7"},
             "postgis_raster": {"default_version": "3.5.7"},
             "postgis_sfcgal": null}
            """);

    assertEquals(
        json(
            """
            {"postgis": {"default_version": "3.5.7"},
             "postgis_raster": {"default_version": "3.5.7"}}
            """),
        ControlDirectives.resolveAll(objectMapper, controls, correction));

    var unreplaced =
        assertThrows(
            IllegalArgumentException.class,
            () ->
                ControlDirectives.resolveAll(
                    objectMapper,
                    controls,
                    json("{\"postgis\": {\"default_version\": \"3.5.7\"}}")));
    assertTrue(
        unreplaced.getMessage().startsWith("control.postgis_raster.default_version"),
        unreplaced.getMessage());

    var unknown =
        assertThrows(
            IllegalArgumentException.class,
            () ->
                ControlDirectives.resolveAll(
                    objectMapper, controls, json("{\"postgis_topology\": null}")));
    assertTrue(unknown.getMessage().startsWith("control.postgis_topology"), unknown.getMessage());
  }
}
