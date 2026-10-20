package dev.monogres.monobot.about;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
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
          "readme": "README.md"
        }
      }
      """;

  private ObjectNode resolve(
      String override, String control, String meta, String upstream, String ref) {
    return resolve(override, control, meta, upstream, ref, null);
  }

  private ObjectNode resolve(
      String override,
      String control,
      String meta,
      String upstream,
      String ref,
      Map<String, JsonNode> contrib) {
    return AboutResolver.resolve(
        objectMapper,
        new AboutResolver.Inputs(
            override == null ? null : json(override),
            // The entry's only control file, keyed by its extension as control.json keys it.
            control == null ? null : objectMapper.createObjectNode().set("fixture", json(control)),
            meta == null ? null : json(meta),
            upstream == null ? null : json(upstream),
            REPO_URL,
            ref,
            contrib));
  }

  private ObjectNode all() {
    return resolve(null, CONTROL, META, UPSTREAM, null);
  }

  /// `\dx` shows the control comment, so it is the short description whenever there is one.
  @Test
  void descriptionPrecedence() {
    assertEquals("control comment", all().path("description").asText());
    assertEquals(
        "meta abstract", resolve(null, null, META, UPSTREAM, null).path("description").asText());
    assertEquals(
        "forge about",
        resolve(null, null, null, "{\"forge\": {\"description\": \"forge about\"}}", null)
            .path("description")
            .asText());
  }

  /// The forge's About is the project describing itself, which is what the long one is for.
  @Test
  void longDescriptionPrecedence() {
    assertEquals("forge about", all().path("long_description").asText());
    assertEquals(
        "meta description",
        resolve(null, CONTROL, META, "{}", null).path("long_description").asText());
    assertEquals(
        "meta abstract",
        resolve(null, CONTROL, "{\"abstract\": \"meta abstract\"}", "{}", null)
            .path("long_description")
            .asText());
  }

  @Test
  void homepagePrecedence() {
    assertEquals("https://forge.example.com", all().path("homepage").asText());
    assertEquals(
        "https://meta.example.com",
        resolve(null, null, META, "{}", null).path("homepage").asText());
  }

  /// With no homepage named anywhere, the repository is where a reader is sent.
  @Test
  void homepageFallsBackToTheRepository() {
    var about = resolve(null, null, null, "{}", null);

    assertEquals(REPO_URL, about.path("homepage").asText());
  }

  /// The forge reads the licence file itself, so it is believed over what anyone wrote down.
  @Test
  void licensePrecedence() {
    assertEquals("MIT", all().path("license").asText());
    assertEquals(
        "PostgreSQL",
        resolve(null, null, META, UPSTREAM.replace("\"MIT\"", "\"NOASSERTION\""), null)
            .path("license")
            .asText());
    assertFalse(
        resolve(null, null, null, UPSTREAM.replace("\"MIT\"", "\"NOASSERTION\""), null)
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
        REPO_URL, resolve(null, null, null, "{}", null).path("repository").path("url").asText());
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

    var about = resolve(override, CONTROL, META, UPSTREAM, null);

    assertEquals("o description", about.path("description").asText());
    assertEquals("o long", about.path("long_description").asText());
    assertEquals("https://o.example.com", about.path("homepage").asText());
    assertEquals("BSD-2-Clause", about.path("license").asText());
    assertEquals(json("[\"O\"]"), about.path("maintainers"));
    assertEquals(json("[\"o\"]"), about.path("keywords"));
    assertEquals(json("[\"O\"]"), about.path("categories"));
    assertEquals("https://gitlab.com/o/o", about.path("repository").path("url").asText());
  }

  /// The README the snapshot found is linked at the version's own ref, on the forge's spelling of
  /// the repository.
  @Test
  void versionCarriesItsRefAndReadme() {
    var about = resolve(null, null, null, UPSTREAM, "v1.0.0");

    assertEquals("v1.0.0", about.path("ref").asText());
    assertEquals(
        "https://raw.githubusercontent.com/monogres/renamed/v1.0.0/README.md",
        about.path("readme").asText());
  }

  /// A README the snapshot did not find is not linked, and a version with no ref has neither.
  @Test
  void noReadmeUnlessFoundAtTheRef() {
    var about = resolve(null, null, null, "{\"forge\": {\"url\": \"" + REPO_URL + "\"}}", "v0.9.0");
    assertEquals("v0.9.0", about.path("ref").asText());
    assertFalse(about.has("readme"), "a README nobody found was linked: " + about);

    var unreffed = resolve(null, null, null, UPSTREAM, null);
    assertFalse(unreffed.has("ref") || unreffed.has("readme"), "unreffed: " + unreffed);
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

    var about = resolve(override, null, null, upstream, null, contrib).path("contrib");

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

  /// The control file is reported as its directives, without the comment the description already
  /// carries, and patched by this version's correction where the build fills a value in.
  @Test
  void controlIsTheDirectivesPatchedByTheCorrection() {
    var controls =
        """
        {"pg_graphql": {"default_version": "@CARGO_VERSION@", "comment": "GraphQL support",
                        "relocatable": false, "superuser": true, "trusted": false,
                        "schema": "graphql"},
         "pg_graphql_extra": {"default_version": "1.0", "comment": "another extension"}}
        """;
    var about =
        AboutResolver.resolve(
            objectMapper,
            new AboutResolver.Inputs(
                null,
                json(controls),
                null,
                null,
                REPO_URL,
                null,
                null,
                null,
                json("{\"pg_graphql\": {\"default_version\": \"1.6.1\"}}"),
                "pg_graphql"));

    assertEquals("GraphQL support", about.path("description").asText());
    assertEquals(
        json(
            """
            {"pg_graphql": {"default_version": "1.6.1", "superuser": true, "trusted": false,
                            "relocatable": false, "schema": "graphql"},
             "pg_graphql_extra": {"default_version": "1.0"}}
            """),
        about.path("control"));
  }

  @Test
  void contribCarriesItsControlAndNamesItWhenItIsWrong() {
    var contrib =
        Map.<String, JsonNode>of(
            "earthdistance",
            json(
                """
                {"default_version": "1.1", "comment": "great-circle distances",
                 "requires": ["cube"], "superuser": true, "trusted": false, "relocatable": true}
                """));

    var about = resolve(null, null, null, null, null, contrib);

    assertEquals(
        json(
            """
            {"earthdistance": {"default_version": "1.1", "requires": ["cube"], "superuser": true,
                               "trusted": false, "relocatable": true}}
            """),
        about.path("contrib").path("earthdistance").path("control"));

    var error =
        assertThrows(
            IllegalArgumentException.class,
            () ->
                resolve(
                    null,
                    null,
                    null,
                    null,
                    null,
                    Map.of("cube", json("{\"default_version\": \"@EXTVERSION@\"}"))));
    assertTrue(
        error.getMessage().startsWith("contrib.cube.control.cube.default_version"),
        error.getMessage());
  }

  /// An extension a flavor builds out of a repository of its own (babelfish's from
  /// babelfish_extensions) is tagged there rather than at the flavor's ref.
  @Test
  void contribFromItsOwnRepositoryCarriesItsOwnRef() {
    var override =
        """
        {"contrib": {"babelfishpg_tsql": {"description": "T-SQL",
          "repository": {"url": "https://github.com/babelfish-for-postgresql/babelfish_extensions",
                         "index": "ext.json"}}}}
        """;
    var about =
        AboutResolver.resolve(
            objectMapper,
            new AboutResolver.Inputs(
                json(override),
                null,
                null,
                null,
                REPO_URL,
                "BABEL_5_4_0__PG_17_7",
                Map.of(),
                Map.of("babelfishpg_tsql", "BABEL_5_4_0")));

    assertEquals(
        "BABEL_5_4_0", about.path("contrib").path("babelfishpg_tsql").path("ref").asText());
  }

  @Test
  void nothingInIsNothingOut() {
    var about =
        AboutResolver.resolve(
            objectMapper, new AboutResolver.Inputs(null, null, null, null, null, null, null));

    assertTrue(about.isEmpty(), "an empty entry was described as " + about);
  }
}
