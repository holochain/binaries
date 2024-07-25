#!/usr/bin/env bash

set -x

tag=$1
name=$2
platform=$3

gh release download "$tag" --pattern "$name-$platform" --repo holochain/holochain
chmod +x "$name-$platform"
set +e
"./$name-$platform" --version
result=$?
set -e
echo "Exporting result ot $GITHUB_OUTPUT"
echo "$name-result=[$result]" >> "$GITHUB_OUTPUT"
