"""
Extensions build configuration.
"""

load("@pgext_ddsketch//:repo.bzl", "METADATA", "REPO_NAME", "VERSIONS")
load("//extensions:cfg.bzl", "cfg")
load("//postgres:cfg.bzl", PG_CFG = "CFG")

CFG = cfg.new(
    name = "ddsketch",
    versions = VERSIONS,
    pg_targets = PG_CFG.targets,
    repo_name = REPO_NAME,
    metadata = METADATA,

)
