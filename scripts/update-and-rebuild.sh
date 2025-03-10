#!/usr/bin/env bash

set -euxo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
OSMOSIS_REV=${1:-main}

LATEST_OSMOSIS_VERSION="v13"

# if "$OSMOIS_REV" is /v\d+/ then extract it as var
if [[ "$OSMOSIS_REV" =~ ^v[0-9]+ ]]; then
  OSMOSIS_VERSION=$(echo "$OSMOSIS_REV" | sed "s/\..*$//")
else
  OSMOSIS_VERSION="$LATEST_OSMOSIS_VERSION"
fi

####################################
## Update and rebuild osmosis-std ##
####################################

# update revision in proto-build main.rs
PROTO_BUILD_MAIN_RS="$SCRIPT_DIR/../packages/proto-build/src/main.rs"

# use @ as a separator to avoid confusion on input like "origin/main"
sed -i "s@const OSMOSIS_REV: \&str = \".*\";@const OSMOSIS_REV: \&str = \"$OSMOSIS_REV\";@g" "$PROTO_BUILD_MAIN_RS"

git diff

# rebuild osmosis-std
cd "$SCRIPT_DIR/../packages/proto-build/" && cargo run -- --update-deps

########################################
## Update and rebuild osmosis-testing ##
########################################

# submodules already updated due to `cargo run -- --update-deps`


# build and run update-osmosis-testing
cd "$SCRIPT_DIR/update-osmosis-testing-replace" && go build
UPDATE_OSMOSIS_TESTING_REPLACE_BIN="$SCRIPT_DIR/update-osmosis-testing-replace/update-osmosis-testing-replace"

# run update-osmosis-testing-replace which will replace the `replace directives` in osmosis-testing
# with osmosis'
$UPDATE_OSMOSIS_TESTING_REPLACE_BIN


cd "$SCRIPT_DIR/../packages/osmosis-testing/libosmosistesting"

# sync rev
go get "github.com/osmosis-labs/osmosis/$OSMOSIS_VERSION@$(echo "$OSMOSIS_REV" | sed "s/^origin\///")"

# tidy up updated go.mod
go mod tidy


########################################
## Update git revision if there is    ##
## any change                         ##
########################################

# if dirty or untracked file exists
if [[ $(git diff --stat) != '' ||  $(git ls-files  --exclude-standard  --others) ]]; then
  # add, commit and push
  git add "$SCRIPT_DIR/.."
  git commit -m "rebuild with $(git rev-parse --short HEAD:dependencies/osmosis)"

  # remove "origin/"
  OSMOSIS_REV=$(echo "$OSMOSIS_REV" | sed "s/^origin\///")
  BRANCH="autobuild-$OSMOSIS_REV"

  # force delete local "$BRANCH" if exists
  git branch -D "$BRANCH" || true

  git checkout -b "$BRANCH"
  git push -uf origin "$BRANCH"
else
  echo '[CLEAN] No update needed for this build'
fi
