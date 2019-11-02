#!/bin/bash

# Proof of concept:
# * Build two Docker images
# * Deconstruct them into a directory with skopeo
# * Merge the layers together, and update digests in manifest/config
# * Reconstruct a merged Docker image with skopeo
# * Show the Docker history of the reconstructed image, and show that
#   files from both images can be accessed in the merged image.

# Requirements (Mac)
# ----------------------------
# $ brew install skopeo jq

set -e
rm -rf /tmp/docker-merge-test
docker rmi -f docker-merge-test || true

mkdir -p /tmp/docker-merge-test
cd /tmp/docker-merge-test

cat > Dockerfile.a <<DOCKERFILE
FROM debian:stretch
RUN echo "foo" > /tmp/a
DOCKERFILE

cat > Dockerfile.b <<DOCKERFILE
FROM debian:stretch
RUN echo "bar" > /tmp/b
DOCKERFILE

docker build -t docker-merge-test:a -f Dockerfile.a .
docker build -t docker-merge-test:b -f Dockerfile.b .

mkdir a b
skopeo --insecure-policy copy docker-daemon:docker-merge-test:a dir:./a/
skopeo --insecure-policy copy docker-daemon:docker-merge-test:b dir:./b/

mkdir -p merged/layers

# Use the version, manifest, and config from a
echo "=> Copy Version: a/version => merged/version"
cp "a/version" merged/version
echo "=> Copy Manifest: a/manifest.json => merged/manifest.json"
cp "a/manifest.json" merged/manifest.json

A_CONFIG_DIGEST=$(jq -r '.config.digest | gsub("sha256:";"")' a/manifest.json)
echo "=> Copy Config: a/$A_CONFIG_DIGEST => merged/config.json"
cp "a/$A_CONFIG_DIGEST" merged/config.json

A_LAYER_DIGESTS=$(jq -r '.layers[].digest | gsub("sha256:";"")' a/manifest.json)
for DIGEST in $A_LAYER_DIGESTS; do
  echo "=> Copy Layer: a/$DIGEST => merged/layers"
  cp "a/$DIGEST" merged/layers
done

B_LAYER_DIGESTS=$(jq -r '.layers[].digest | gsub("sha256:";"")' b/manifest.json)
for DIGEST in $B_LAYER_DIGESTS; do
  if [ -f "merged/layers/$DIGEST" ]; then
    echo "=> merged/layers/$DIGEST already exists"
    continue
  fi
  echo "=> Copy Layer: b/$DIGEST => merged/layers"
  cp "b/$DIGEST" merged/layers
done

BASE_LAYER=$(jq -r '.layers[0].digest | gsub("sha256:";"")' b/manifest.json)

# Manual steps (for now):
# ---------------------------------------------
# Add b layer to history array in config.json
# Add b layer to rootfs.diffids in config.json
# Add b layer to layers array in manifest.json

# Minify JSON for merged/config.json
MERGED_CONFIG_DIGEST=$(cat merged/config.json | sha256sum | cut -d" " -f1)
MERGED_CONFIG_SIZE=$(wc -c < merged/config.json | sed "s/ //g")
echo "merged/config.json size: $MERGED_CONFIG_SIZE, digest: $MERGED_CONFIG_DIGEST"

# Rename config.json to the digest filename
mv merged/config.json "merged/$MERGED_CONFIG_DIGEST"

# Update config digest in manifest
jq -c ".config.digest = \"sha256:$MERGED_CONFIG_DIGEST\" | \
.config.size = $MERGED_CONFIG_SIZE" merged/manifest.json > merged/manifest.json.tmp
mv merged/manifest.json.tmp merged/manifest.json

# Move all layers into the root directory
mv merged/layers/* merged/
rm -rf merged/layers/

# Build the merged Docker image
skopeo --insecure-policy copy dir:./merged/ docker-daemon:docker-merge-test:merged

docker history docker-merge-test:merged
# IMAGE               CREATED             CREATED BY                                      SIZE                COMMENT
# 45a010354d0f        41 minutes ago      /bin/sh -c echo "bar" > /tmp/b                  4B
# <missing>           41 minutes ago      /bin/sh -c echo "foo" > /tmp/a                  4B
# <missing>           2 weeks ago         /bin/sh -c #(nop)  CMD ["bash"]                 0B
# <missing>           2 weeks ago         /bin/sh -c #(nop) ADD file:fdf0128645db4c8b9…   101MB

docker run --rm docker-merge-test:merged bash -c "cat /tmp/a /tmp/b"
# foo
# bar


# It works!!!
