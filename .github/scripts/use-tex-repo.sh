#!/usr/bin/env bash

# Point MiKTeX at the package repository that the cache entry carries, so
# that a package install which a compile starts reads a folder rather than
# a server. MIKTEX_REPOSITORY names the repository for every program of
# MiKTeX, see mpm(1), and a later step of the job reads it because the
# name goes into the environment of the job.
#
# A package that the repository does not hold now fails at once, which is
# the point: an install that waits on a server cannot be answered from a
# job, and a compile that waits on that install reaches its own limit with
# nothing to show. The folder is also printed, because what the entry
# carries is otherwise only visible when something needs it.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/46

set -u

repo=${TEX_REPO:?TEX_REPO must name the folder of the repository.}

if [ ! -d "$repo" ]; then
  echo "::error::$repo is not a folder, so the entry carries no package repository. .github/scripts/make-tex-repo.sh writes it, in the workflow that saves the entry."
  exit 1
fi

echo "The repository holds:"
ls -l "$repo"

echo "MIKTEX_REPOSITORY=$repo" >> "$GITHUB_ENV"

# MiKTeX reads the database of the repository, which is the work it would
# otherwise do over the network at the first install of a compile. It also
# answers whether the folder is a repository at all.
if ! said=$(miktex packages update-package-database --repository "$repo" 2>&1); then
  printf '%s\n' "$said"
  echo "::error::MiKTeX refused $repo as a package repository. Everything it said is above."
  exit 1
fi
printf '%s\n' "$said"
