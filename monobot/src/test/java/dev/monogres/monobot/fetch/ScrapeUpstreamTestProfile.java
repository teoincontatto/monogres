package dev.monogres.monobot.fetch;

import java.util.HashMap;
import java.util.Map;

/// A generate run that is allowed to ask the upstream about an entry. Every other test runs with
/// `scrapeUpstream` off, which is the `%test` default, so none of them reaches the network; this
/// one turns it on and mocks what would answer.
public class ScrapeUpstreamTestProfile extends PipelineTestProfile {
  @Override
  public Map<String, String> getConfigOverrides() {
    var overrides = new HashMap<>(super.getConfigOverrides());
    overrides.put("scrapeUpstream", "true");

    return overrides;
  }
}
