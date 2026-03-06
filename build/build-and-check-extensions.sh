#!/bin/bash

cd "$(dirname "$0")"

mkdir -p target

if ! [ -f target/bazel-query.out ]
then
  echo "Running bazel query..."
  if ! bazel query ... > target/bazel-query.out 2>&1
  then
    mv target/bazel-query.out target/bazel-query.err
    echo "Query failed"
    exit 1
  fi
  grep //extensions/ target/bazel-query.out | grep -v -- '--' > target/extensions-targets
fi
if ! [ -f target/extensions-targets-bazel-build.out ] \
  || [ "$(stat -c %Y target/extensions-targets)" -gt "$(stat -c %Y target/extensions-targets-bazel-build.out)" ]
then
  echo "Running bazel build..."
  cat target/extensions-targets | xargs bazel build > target/extensions-targets-bazel-build.out 2>&1
fi
grep '~postgres.*~[0-9]\+\.[0-9]\+' target/extensions-targets | grep -v '^//extensions/contrib:' | sort > target/external-extensions-targets
grep '~postgres.*~[0-9]\+\.[0-9]\+' target/extensions-targets | grep '^//extensions/contrib:' | sort > target/contrib-extensions-targets
while IFS=':~' read EXTENSION_PATH EXTENSION_NAME EXTENSION_VERSION POSTGRES_FLAVOR POSTGRES_VERSION
do
  if ! [ -f "bazel-out/k8-fastbuild/bin/extensions/${EXTENSION_NAME}/${EXTENSION_NAME}~${EXTENSION_VERSION}~${POSTGRES_FLAVOR}~${POSTGRES_VERSION}.tar" ]
  then
    echo "[ERROR]   Extension $EXTENSION_NAME ${EXTENSION_VERSION} for ${POSTGRES_FLAVOR} ${POSTGRES_VERSION} was not built"
  else
    echo "[SUCCESS] Extension $EXTENSION_NAME ${EXTENSION_VERSION} for ${POSTGRES_FLAVOR} ${POSTGRES_VERSION} was built"
  fi
done < target/external-extensions-targets