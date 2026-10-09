package dev.monogres.monobot.config.input;

import com.fasterxml.jackson.annotation.JsonCreator;
import io.quarkus.runtime.annotations.RegisterForReflection;
import java.util.Locale;

/// What kind of thing an entry catalogues, which decides what its archives are read for.
///
/// An extension's archive is read for its own control file and its META.json. A Postgres flavor's
/// is read for the control files of every extension it builds with itself, its contrib modules and
/// procedural languages, which is what describes them. An addon is software shipped beside Postgres
/// rather than inside it, and its archive answers for nothing but its digest.
@RegisterForReflection
public enum ComponentType {
  POSTGRES,
  EXTENSION,
  ADDON;

  /// Spelled in lowercase in `monobot.json`, like every other value there.
  @JsonCreator
  public static ComponentType of(String spelling) {
    return valueOf(spelling.toUpperCase(Locale.ROOT));
  }
}
