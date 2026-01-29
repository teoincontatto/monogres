"""
Extensions build configuration.
"""

load("@pgext_citus//:repo.bzl", "METADATA", "REPO_NAME", "VERSIONS")
load("//extensions:cfg.bzl", "cfg")
load("//postgres:cfg.bzl", PG_CFG = "CFG")

CFG = cfg.new(
    name = "citus",
    versions = VERSIONS,
    pg_targets = PG_CFG.targets,
    repo_name = REPO_NAME,
    buildtime_dependencies = [
        "@pgext_citus_deps_debian13//libcurl4-openssl-dev",
        "@pgext_citus_deps_debian13//libicu-dev",
        "@pgext_citus_deps_debian13//libkrb5-dev",
        "@pgext_citus_deps_debian13//liblz4-dev",
        "@pgext_citus_deps_debian13//libssl-dev",
        "@pgext_citus_deps_debian13//libzstd-dev",
    ],
    runtime_dependencies = [
        "@pgext_citus_deps_debian13//libcurl4t64",
        "@pgext_citus_deps_debian13//liblz4-1",
        "@pgext_citus_deps_debian13//libzstd1",
    ],
    metadata = METADATA,
)
