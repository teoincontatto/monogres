package dev.monogres.monobot.about;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.monogres.monobot.config.output.Version;
import java.util.LinkedHashMap;
import java.util.List;
import org.junit.jupiter.api.Test;

class LayersTest {
  private final ObjectMapper objectMapper = new ObjectMapper();

  private ObjectNode json(String json) throws Exception {
    return (ObjectNode) objectMapper.readTree(json);
  }

  private LinkedHashMap<String, ObjectNode> documents() throws Exception {
    var documents = new LinkedHashMap<String, ObjectNode>();
    documents.put(
        "2.0",
        json(
            """
            {"description": "new", "license": "MIT", "keywords": ["a", "b"],
             "repository": {"url": "https://x/y"}, "ref": "v2.0",
             "contrib": {"one": {"description": "one"}, "two": {"description": "two"}}}
            """));
    documents.put(
        "1.1",
        json(
            """
            {"description": "new", "license": "MIT", "keywords": ["a", "b"],
             "repository": {"url": "https://x/y"}, "ref": "v2.0",
             "contrib": {"one": {"description": "one"}, "two": {"description": "two"}}}
            """));
    documents.put(
        "1.0",
        json(
            """
            {"description": "old", "keywords": ["a"],
             "repository": {"url": "https://x/y"}, "ref": "v1.0",
             "contrib": {"one": {"description": "the first"}}}
            """));

    return documents;
  }

  /// The newest version is held whole and named; the older ones are what changed going back, and a
  /// version that changed nothing is still listed.
  @Test
  void layersNewestFirstAndOnlyWhatChanged() throws Exception {
    assertEquals(
        json(
            """
            {
              "latest": {
                "version": "2.0", "description": "new", "license": "MIT", "keywords": ["a", "b"],
                "repository": {"url": "https://x/y"}, "ref": "v2.0",
                "contrib": {"one": {"description": "one"}, "two": {"description": "two"}}
              },
              "versions": {
                "1.1": {},
                "1.0": {
                  "description": "old", "license": null, "keywords": ["a"], "ref": "v1.0",
                  "contrib": {"one": {"description": "the first"}, "two": null}
                }
              }
            }
            """),
        Layers.layer(objectMapper, documents()));
  }

  @Test
  void resolveIsTheInverseOfLayer() throws Exception {
    var documents = documents();

    assertEquals(documents, Layers.resolve(Layers.layer(objectMapper, documents)));
    assertEquals(
        List.of("2.0", "1.1", "1.0"),
        List.copyOf(Layers.resolve(Layers.layer(objectMapper, documents)).keySet()));
  }

  @Test
  void singleVersionIsOnlyLatest() throws Exception {
    var documents = new LinkedHashMap<String, ObjectNode>();
    documents.put("1.0", json("{\"description\": \"one\"}"));

    var layered = Layers.layer(objectMapper, documents);

    assertEquals(json("{\"latest\": {\"version\": \"1.0\", \"description\": \"one\"}}"), layered);
  }

  @Test
  void anUnlayeredDocumentHoldsNoVersion() throws Exception {
    assertTrue(Layers.resolve(json("{\"description\": \"flat\"}")).isEmpty());
  }

  @Test
  void applyMergesObjectsReplacesTheRestAndRemovesNulls() throws Exception {
    JsonNode merged =
        Layers.apply(
            json("{\"a\": {\"b\": 1, \"c\": 2}, \"d\": [1, 2], \"e\": \"x\"}"),
            json("{\"a\": {\"c\": null, \"f\": 3}, \"d\": [3], \"e\": null}"));

    assertEquals(json("{\"a\": {\"b\": 1, \"f\": 3}, \"d\": [3]}"), merged);
  }

  /// An override's patch applies to the version it is keyed on and every older one, whether or
  /// not that version is catalogued.
  @Test
  void anOverridePatchAppliesToItsVersionAndOlder() throws Exception {
    var override =
        json(
            """
            {
              "latest": {"description": "now", "license": "MIT"},
              "versions": {
                "1.5": {"license": "GPL-2.0-only"},
                "1.0": {"description": "then"}
              }
            }
            """);

    var resolved =
        Layers.override(
            override,
            List.of(
                new Version("2.0"), new Version("1.2"), new Version("1.0"), new Version("0.9")));

    assertEquals(json("{\"description\": \"now\", \"license\": \"MIT\"}"), resolved.get("2.0"));
    assertEquals(
        json("{\"description\": \"now\", \"license\": \"GPL-2.0-only\"}"), resolved.get("1.2"));
    assertEquals(
        json("{\"description\": \"then\", \"license\": \"GPL-2.0-only\"}"), resolved.get("1.0"));
    assertEquals(
        json("{\"description\": \"then\", \"license\": \"GPL-2.0-only\"}"), resolved.get("0.9"));
  }

  @Test
  void noOverrideIsNullAtEveryVersion() {
    var resolved =
        Layers.override(
            objectMapper.missingNode(), List.of(new Version("2.0"), new Version("1.0")));

    assertNull(resolved.get("2.0"));
    assertNull(resolved.get("1.0"));
  }
}
