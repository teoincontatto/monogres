package dev.monogres.monobot.about;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/// What a forge says about a repository: the "About" line, the homepage, the licence it detected,
/// the topics, and which file is the README at a given ref.
///
/// Blocking, on purpose. It is called from the ordered block that already reads every archive of an
/// entry, a handful of requests per entry against APIs that rate limit by the hour, so there is
/// nothing to gain from overlapping them and a great deal to lose from a burst.
///
/// Redirects are followed: GitHub answers a renamed or transferred repository with a 301 to its
/// new home (`zalando/patroni` is `patroni/patroni`), and the repository's own `html_url` in the
/// answer is what the snapshot records.
@ApplicationScoped
public class UpstreamClient {
  private static final String GITHUB_API = "https://api.github.com/repos/";
  private static final String GITLAB_API = "https://gitlab.com/api/v4/projects/";
  private static final String USER_AGENT = "monobot";
  private static final int OK = 200;
  private static final int NOT_FOUND = 404;
  private static final int ATTEMPTS = 3;

  private static final Logger LOG = Logger.getLogger(UpstreamClient.class);

  /// The files a GitLab README is looked for under, in order, when the project names none.
  private static final String[] GITLAB_README_CANDIDATES = {"README.md", "README", "README.rst"};

  @ConfigProperty(name = "githubToken")
  Optional<String> githubToken;

  @ConfigProperty(name = "gitlabToken")
  Optional<String> gitlabToken;

  @ConfigProperty(name = "downloadTimeout")
  Duration timeout;

  @Inject ObjectMapper objectMapper;

  private final HttpClient http =
      HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NORMAL).build();

  /// The repository as the forge describes it, in the snapshot's own shape so that what is
  /// committed is the same whichever forge answered. Empty when the forge has no such repository.
  public Optional<ObjectNode> repository(Forge forge) {
    return switch (forge.kind()) {
      case GITHUB -> get(GITHUB_API + forge.project(), github()).map(this::fromGithub);
      case GITLAB ->
          get(GITLAB_API + Forge.encoded(forge.project()) + "?license=true", gitlab())
              .map(this::fromGitlab);
    };
  }

  /// The path of the README at `ref`, or empty when there is none there.
  public Optional<String> readme(Forge forge, String ref) {
    return switch (forge.kind()) {
      case GITHUB ->
          get(GITHUB_API + forge.project() + "/readme?ref=" + Forge.encoded(ref), github())
              .map(readme -> readme.path("path").asText(null));
      case GITLAB -> {
        for (var candidate : GITLAB_README_CANDIDATES) {
          var file =
              get(
                  GITLAB_API
                      + Forge.encoded(forge.project())
                      + "/repository/files/"
                      + Forge.encoded(candidate)
                      + "?ref="
                      + Forge.encoded(ref),
                  gitlab());
          if (file.isPresent()) {
            yield Optional.of(candidate);
          }
        }
        yield Optional.empty();
      }
    };
  }

  private ObjectNode fromGithub(JsonNode repo) {
    var snapshot = objectMapper.createObjectNode();
    snapshot.put("kind", "github");
    snapshot.put("url", repo.path("html_url").asText());
    putText(snapshot, "description", repo.path("description"));
    putText(snapshot, "homepage", repo.path("homepage"));
    putText(snapshot, "license", repo.path("license").path("spdx_id"));
    snapshot.set("topics", repo.path("topics").isArray() ? repo.get("topics") : array());

    return snapshot;
  }

  private ObjectNode fromGitlab(JsonNode project) {
    var snapshot = objectMapper.createObjectNode();
    snapshot.put("kind", "gitlab");
    snapshot.put("url", project.path("web_url").asText());
    putText(snapshot, "description", project.path("description"));
    // GitLab keeps no homepage of a project's own. What it names a licence by is a lowercase key
    // rather than an SPDX id, which is normalised later along with every other spelling.
    putText(snapshot, "license", project.path("license").path("key"));
    snapshot.set("topics", project.path("topics").isArray() ? project.get("topics") : array());

    return snapshot;
  }

  private JsonNode array() {
    return objectMapper.createArrayNode();
  }

  private static void putText(ObjectNode into, String field, JsonNode value) {
    if (value.isTextual() && !value.asText().isBlank()) {
      into.put(field, value.asText().strip());
    } else {
      into.putNull(field);
    }
  }

  private Map<String, String> github() {
    var headers = new LinkedHashMap<String, String>();
    headers.put("Accept", "application/vnd.github+json");
    headers.put("X-GitHub-Api-Version", "2022-11-28");
    githubToken
        .filter(token -> !token.isBlank())
        .ifPresent(token -> headers.put("Authorization", "Bearer " + token));

    return headers;
  }

  private Map<String, String> gitlab() {
    var headers = new LinkedHashMap<String, String>();
    gitlabToken
        .filter(token -> !token.isBlank())
        .ifPresent(token -> headers.put("PRIVATE-TOKEN", token));

    return headers;
  }

  /// A JSON document, empty on a 404, and an exception on anything else that is not a 200. A 403
  /// from a rate limit is the usual reason, and it is not an answer about the repository: taking it
  /// for "no such repository" would commit a snapshot that says so.
  Optional<JsonNode> get(String url, Map<String, String> headers) {
    var response = send(url, headers);

    if (response.statusCode() == NOT_FOUND) {
      return Optional.empty();
    }
    if (response.statusCode() != OK) {
      throw new UpstreamException(
          url + " answered " + response.statusCode() + ": " + new String(response.body()), null);
    }

    try {
      return Optional.of(objectMapper.readTree(response.body()));
    } catch (IOException e) {
      throw new UpstreamException(url + " answered something that is not JSON", e);
    }
  }

  /// Raw bytes, for a document that is not JSON. Same rules as [#get].
  byte[] getBytes(String url) {
    var response = send(url, Map.of());
    if (response.statusCode() != OK) {
      throw new UpstreamException(url + " answered " + response.statusCode(), null);
    }

    return response.body();
  }

  /// One request, tried again when the connection fails under it. GitHub closes idle HTTP/2
  /// connections, and the client finds out by reading EOF on the next request it sends down one:
  /// an I/O error that says nothing about the repository. An answer, whatever its status, is not
  /// retried.
  private HttpResponse<byte[]> send(String url, Map<String, String> headers) {
    var request =
        HttpRequest.newBuilder(URI.create(url)).timeout(timeout).header("User-Agent", USER_AGENT);
    headers.forEach(request::header);

    IOException failure = null;
    for (var attempt = 1; attempt <= ATTEMPTS; attempt++) {
      try {
        return http.send(request.GET().build(), HttpResponse.BodyHandlers.ofByteArray());
      } catch (IOException e) {
        failure = e;
        LOG.debugv(e, "{0} failed on attempt {1}", url, attempt);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw new UpstreamException(url + " was interrupted", e);
      }
    }

    throw new UpstreamException(url + " could not be asked", failure);
  }

  public static class UpstreamException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    public UpstreamException(String message, Throwable cause) {
      super(message, cause);
    }
  }
}
