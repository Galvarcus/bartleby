#!/usr/bin/env bash

# Fail unless the job runs in the CI image. With the repository variable
# CI_IMAGE unset, GitHub runs the job on the bare runner instead, where
# the smoke tests skip themselves for want of pandoc and TeX, and pass.

if [ -z "${PANDOC_RELEASE:-}" ] || [ ! -x "/opt/pandoc-$PANDOC_RELEASE/bin/pandoc" ]; then
  echo "::error::This job is not running in the CI image. Set the repository variable CI_IMAGE to a tag of ghcr.io/galvarcus/bartleby-ci, see .github/workflows/ci-image.yml."
  exit 1
fi
echo "Running in the CI image, with pandoc $PANDOC_RELEASE."
