package dev.monogres.monobot.fetch;

import java.util.HashMap;
import java.util.Map;

/// A generate run that asks the upstream again about what the snapshot already answers for.
public class RefreshUpstreamTestProfile extends ScrapeUpstreamTestProfile {
  @Override
  public Map<String, String> getConfigOverrides() {
    var overrides = new HashMap<>(super.getConfigOverrides());
    overrides.put("refreshUpstream", "true");

    return overrides;
  }
}
