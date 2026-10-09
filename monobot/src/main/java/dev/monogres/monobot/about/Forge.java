package dev.monogres.monobot.about;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Optional;

/// A repository on a forge monobot knows how to ask about, read off the repository's URL.
///
/// Two forges, because they are the two the catalog points at: GitHub for almost every entry and
/// gitlab.com for the rest. A path on gitlab.com can carry nested groups (`ongresinc/extensions/
/// noset`), so the project is the whole path rather than an owner and a name. Anything else, a
/// download server or a project's own website, is a repository nothing can be asked about and
/// [#of] says so with an empty answer.
public record Forge(Kind kind, String project) {
  public enum Kind {
    GITHUB,
    GITLAB
  }

  private static final String GITHUB_HOST = "github.com";
  private static final String GITLAB_HOST = "gitlab.com";
  private static final String SUFFIX_GIT = ".git";

  public static Optional<Forge> of(String repositoryUrl) {
    if (repositoryUrl == null || repositoryUrl.isBlank()) {
      return Optional.empty();
    }

    URI uri;
    try {
      uri = URI.create(repositoryUrl.strip());
    } catch (IllegalArgumentException e) {
      return Optional.empty();
    }

    if (uri.getHost() == null || uri.getPath() == null) {
      return Optional.empty();
    }

    var project = uri.getPath().replaceAll("^/+|/+$", "");
    if (project.endsWith(SUFFIX_GIT)) {
      project = project.substring(0, project.length() - SUFFIX_GIT.length());
    }
    // A link into a tree or a blob is still the repository it is in. GitLab spells those after a
    // `/-/` separator and GitHub after the owner and the name.
    var separator = project.indexOf("/-/");
    if (separator >= 0) {
      project = project.substring(0, separator);
    }

    return switch (uri.getHost().toLowerCase()) {
      case GITHUB_HOST -> {
        var parts = project.split("/");
        yield parts.length >= 2
            ? Optional.of(new Forge(Kind.GITHUB, parts[0] + "/" + parts[1]))
            : Optional.empty();
      }
      case GITLAB_HOST ->
          project.contains("/") ? Optional.of(new Forge(Kind.GITLAB, project)) : Optional.empty();
      default -> Optional.empty();
    };
  }

  /// The repository's page, which is what a reader is sent to.
  public String webUrl() {
    return switch (kind) {
      case GITHUB -> "https://" + GITHUB_HOST + "/" + project;
      case GITLAB -> "https://" + GITLAB_HOST + "/" + project;
    };
  }

  /// One file at one ref, as its bytes rather than as a page around them.
  public String rawUrl(String ref, String path) {
    return switch (kind) {
      case GITHUB -> "https://raw.githubusercontent.com/" + project + "/" + ref + "/" + path;
      case GITLAB -> webUrl() + "/-/raw/" + ref + "/" + path;
    };
  }

  static String encoded(String value) {
    return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
  }
}
