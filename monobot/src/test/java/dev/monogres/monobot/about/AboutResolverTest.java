package dev.monogres.monobot.about;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.jupiter.api.Test;

/// Each field of `about.json` comes from the first source that says something about it, in an
/// order chosen per field. These pin that order down one field at a time: take the full set of
/// sources, then remove the winner and see the next one win.
class AboutResolverTest {
  private static final String REPO_URL = "https://github.com/monogres/fixture";

  private final ObjectMapper objectMapper = new ObjectMapper();

  private JsonNode json(String text) {
    try {
      return objectMapper.readTree(text);
    } catch (Exception e) {
      throw new AssertionError(e);
    }
  }

  private static final String CONTROL = "{\"comment\": \"control comment\"}";

  private static final String META =
      """
      {
        "abstract": "meta abstract",
        "description": "meta description",
        "license": {"PostgreSQL": "http://www.postgresql.org/about/licence"},
        "maintainer": "Some One <one@example.com>",
        "tags": ["Vectors", "search"],
        "resources": {"homepage": "https://meta.example.com"}
      }
      """;

  private static final String UPSTREAM =
      """
      {
        "forge": {
          "kind": "github",
          "url": "https://github.com/monogres/renamed",
          "description": "forge about",
          "homepage": "https://forge.example.com",
          "license": "MIT",
          "topics": ["vectors", "postgres"],
          "readme": {"v1.0.0": "README.md", "v0.9.0": null}
        }
      }
      """;

  private ObjectNode resolve(
      String override, String control, String meta, String upstream, Map<String, String> refs) {
    return resolve(override, control, meta, upstream, refs, Map.of());
  }

  private ObjectNode resolve(
      String override,
      String control,
      String meta,
      String upstream,
      Map<String, String> refs,
      Map<String, JsonNode> contrib) {
    return AboutResolver.resolve(
        objectMapper,
        new AboutResolver.Inputs(
            override == null ? null : json(override),
            control == null ? null : json(control),
            meta == null ? null : json(meta),
            upstream == null ? null : json(upstream),
            REPO_URL,
            new LinkedHashMap<>(refs),
            contrib));
  }

  private ObjectNode all() {
    return resolve(null, CONTROL, META, UPSTREAM, Map.of());
  }

  /// `\dx` shows the control comment, so it is the short description whenever there is one.
  @Test
  void descriptionPrecedence() {
    assertEquals("control comment", all().path("description").asText());
    assertEquals(
        "meta abstract",
        resolve(null, null, META, UPSTREAM, Map.of()).path("description").asText());
    assertEquals(
        "forge about",
        resolve(null, null, null, "{\"forge\": {\"description\": \"forge about\"}}", Map.of())
            .path("description")
            .asText());
  }

  /// The forge's About is the project describing itself, which is what the long one is for.
  @Test
  void longDescriptionPrecedence() {
    assertEquals("forge about", all().path("long_description").asText());
    assertEquals(
        "meta description",
        resolve(null, CONTROL, META, "{}", Map.of()).path("long_description").asText());
    assertEquals(
        "meta abstract",
        resolve(null, CONTROL, "{\"abstract\": \"meta abstract\"}", "{}", Map.of())
            .path("long_description")
            .asText());
  }

  @Test
  void homepagePrecedence() {
    assertEquals("https://forge.example.com", all().path("homepage").asText());
    assertEquals(
        "https://meta.example.com",
        resolve(null, null, META, "{}", Map.of()).path("homepage").asText());
  }

  /// With no homepage named anywhere, the repository is where a reader is sent.
  @Test
  void homepageFallsBackToTheRepository() {
    var about = resolve(null, null, null, "{}", Map.of());

    assertEquals(REPO_URL, about.path("homepage").asText());
  }

  /// The forge reads the licence file itself, so it is believed over what anyone wrote down.
  @Test
  void licensePrecedence() {
    assertEquals("MIT", all().path("license").asText());
    assertEquals(
        "PostgreSQL",
        resolve(null, null, META, UPSTREAM.replace("\"MIT\"", "\"NOASSERTION\""), Map.of())
            .path("license")
            .asText());
    assertFalse(
        resolve(null, null, null, UPSTREAM.replace("\"MIT\"", "\"NOASSERTION\""), Map.of())
            .has("license"),
        "a licence nobody named was made up");
  }

  @Test
  void maintainersComeFromMeta() {
    assertEquals(json("[\"Some One <one@example.com>\"]"), all().path("maintainers"));
  }

  /// One keyword spelled two ways is one keyword, and the tag's spelling is kept over the topic's.
  @Test
  void keywordsAreTagsAndTopicsWithoutRepeats() {
    assertEquals(json("[\"Vectors\", \"search\", \"postgres\"]"), all().path("keywords"));
  }

  /// No source classifies an entry, so a category is only ever written by hand.
  @Test
  void categoriesComeOnlyFromTheOverride() {
    assertFalse(all().has("categories"), "a category was derived: " + all());
  }

  /// After a rename, the forge's own spelling of where the repository is wins over the one asked.
  @Test
  void repositoryPrecedence() {
    assertEquals(
        "https://github.com/monogres/renamed", all().path("repository").path("url").asText());
    assertEquals(
        REPO_URL,
        resolve(null, null, null, "{}", Map.of()).path("repository").path("url").asText());
  }

  @Test
  void overrideWinsEveryField() {
    var override =
        """
        {
          "description": "o description",
          "long_description": "o long",
          "homepage": "https://o.example.com",
          "license": "BSD-2-Clause",
          "maintainers": ["O"],
          "keywords": ["o"],
          "categories": ["O"],
          "repository": {"url": "https://gitlab.com/o/o"}
        }
        """;

    var about = resolve(override, CONTROL, META, UPSTREAM, Map.of());

    assertEquals("o description", about.path("description").asText());
    assertEquals("o long", about.path("long_description").asText());
    assertEquals("https://o.example.com", about.path("homepage").asText());
    assertEquals("BSD-2-Clause", about.path("license").asText());
    assertEquals(json("[\"O\"]"), about.path("maintainers"));
    assertEquals(json("[\"o\"]"), about.path("keywords"));
    assertEquals(json("[\"O\"]"), about.path("categories"));
    assertEquals("https://gitlab.com/o/o", about.path("repository").path("url").asText());
  }

  /// A README is linked only where the snapshot found one at that ref; a version with no ref is
  /// still listed, with nothing to say about it.
  @Test
  void versionsCarryTheirRefAndReadme() {
    var refs = new LinkedHashMap<String, String>();
    refs.put("1.0.0", "v1.0.0");
    refs.put("0.9.0", "v0.9.0");
    refs.put("0.8.0", "v0.8.0");
    refs.put("0.7.0", null);

    var versions = resolve(null, null, null, UPSTREAM, refs).path("versions");

    assertEquals(
        json(
            """
            {
              "1.0.0": {
                "ref": "v1.0.0",
                "readme": "https://raw.githubusercontent.com/monogres/renamed/v1.0.0/README.md"
              },
              "0.9.0": {"ref": "v0.9.0"},
              "0.8.0": {"ref": "v0.8.0"},
              "0.7.0": {}
            }
            """),
        versions);
  }

  @Test
  void contribIsDescribedFromItsControlAndOverride() {
    var override =
        """
        {"contrib": {
          "babelfishpg_tsql": {"description": "T-SQL",
            "repository": {"url": "https://github.com/babelfish-for-postgresql/babelfish_extensions"}},
          "hstore": {"homepage": "https://www.postgresql.org/docs/current/hstore.html",
            "categories": ["TYPE"]}}}
        """;
    var upstream =
        """
        {"forge": {"license": "PostgreSQL"}}
        """;
    var contrib =
        Map.<String, JsonNode>of(
            "hstore", json("{\"comment\": \"data type for storing sets of (key, value) pairs\"}"),
            "plperl", json("{\"comment\": \"PL/Perl procedural language\"}"));

    var about = resolve(override, null, null, upstream, Map.of(), contrib).path("contrib");

    assertEquals(
        json(
            """
            {
              "babelfishpg_tsql": {
                "description": "T-SQL",
                "license": "PostgreSQL",
                "repository": {
                  "url": "https://github.com/babelfish-for-postgresql/babelfish_extensions"
                }
              },
              "hstore": {
                "description": "data type for storing sets of (key, value) pairs",
                "long_description": "data type for storing sets of (key, value) pairs",
                "homepage": "https://www.postgresql.org/docs/current/hstore.html",
                "license": "PostgreSQL",
                "categories": ["TYPE"]
              },
              "plperl": {
                "description": "PL/Perl procedural language",
                "long_description": "PL/Perl procedural language",
                "license": "PostgreSQL"
              }
            }
            """),
        about);
  }

  @Test
  void nothingInIsNothingOut() {
    var about =
        AboutResolver.resolve(
            objectMapper, new AboutResolver.Inputs(null, null, null, null, null, null, null));

    assertTrue(about.isEmpty(), "an empty entry was described as " + about);
  }
}
