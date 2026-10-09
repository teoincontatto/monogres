package dev.monogres.monobot.about;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

/// One licence, spelled as an SPDX expression whatever the source spelled it as.
///
/// Each source has a spelling of its own. GitHub gives an SPDX id, or `NOASSERTION` when its
/// detector could not decide, which it says of PostgreSQL's own licence. GitLab gives a lowercase
/// key (`agpl-3.0`). PGXN gives a key of its own (`postgresql`, `gpl_3`), a list of them, or a map
/// from a name to a URL. An answer that says nothing is empty, so the next source gets to say
/// something.
public final class Licenses {
  private Licenses() {}

  /// Lowercase spellings that are not already an SPDX id, from all of the sources above.
  private static final Map<String, String> SPDX =
      Map.ofEntries(
          Map.entry("postgresql", "PostgreSQL"),
          Map.entry("mit", "MIT"),
          Map.entry("isc", "ISC"),
          Map.entry("bsd", "BSD-3-Clause"),
          Map.entry("freebsd", "BSD-2-Clause"),
          Map.entry("bsd-2-clause", "BSD-2-Clause"),
          Map.entry("bsd-3-clause", "BSD-3-Clause"),
          Map.entry("apache_2_0", "Apache-2.0"),
          Map.entry("apache-2.0", "Apache-2.0"),
          Map.entry("apache_1_1", "Apache-1.1"),
          Map.entry("gpl_2", "GPL-2.0"),
          Map.entry("gpl-2.0", "GPL-2.0"),
          Map.entry("gpl_3", "GPL-3.0"),
          Map.entry("gpl-3.0", "GPL-3.0"),
          Map.entry("gpl-2.0+", "GPL-2.0-or-later"),
          Map.entry("gpl-3.0+", "GPL-3.0-or-later"),
          Map.entry("lgpl_2_1", "LGPL-2.1"),
          Map.entry("lgpl-2.1", "LGPL-2.1"),
          Map.entry("lgpl_3_0", "LGPL-3.0"),
          Map.entry("lgpl-3.0", "LGPL-3.0"),
          Map.entry("agpl_3", "AGPL-3.0"),
          Map.entry("agpl-3.0", "AGPL-3.0"),
          Map.entry("mozilla_2_0", "MPL-2.0"),
          Map.entry("mpl-2.0", "MPL-2.0"),
          Map.entry("artistic_2", "Artistic-2.0"),
          Map.entry("zlib", "Zlib"),
          Map.entry("unlicense", "Unlicense"));

  /// What a source says when it is not saying which licence.
  private static final List<String> UNKNOWN =
      List.of(
          "noassertion", "none", "other", "unknown", "open_source", "restricted", "unrestricted");

  /// One spelling, from any source.
  public static Optional<String> of(String spelling) {
    if (spelling == null || spelling.isBlank()) {
      return Optional.empty();
    }

    var key = spelling.strip().toLowerCase(Locale.ROOT);
    if (UNKNOWN.contains(key)) {
      return Optional.empty();
    }

    return Optional.of(SPDX.getOrDefault(key, spelling.strip()));
  }

  /// PGXN's `license`, which is a string, a list of strings, or a map whose keys are the licences.
  /// More than one licence is a choice between them, which SPDX spells with `OR`.
  public static Optional<String> ofPgxn(JsonNode license) {
    if (license == null || license.isMissingNode() || license.isNull()) {
      return Optional.empty();
    }
    if (license.isTextual()) {
      return of(license.asText());
    }

    var names = new ArrayList<String>();
    if (license.isArray()) {
      license.forEach(name -> names.add(name.asText()));
    } else if (license.isObject()) {
      license.fieldNames().forEachRemaining(names::add);
    }

    var known = names.stream().map(Licenses::of).flatMap(Optional::stream).distinct().toList();

    return known.isEmpty() ? Optional.empty() : Optional.of(String.join(" OR ", known));
  }
}
