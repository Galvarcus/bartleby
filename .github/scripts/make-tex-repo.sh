#!/usr/bin/env bash

# Make a local package repository beside the trees that the warm-up
# fills, so that no package work during a compile needs the network.
# MiKTeX reads a directory named by MIKTEX_REPOSITORY as a package
# repository, see mpm(1), and a directory is only a repository when it
# holds the package database. The database is therefore the deliverable
# here and a missing archive of it is an error, while a package archive
# that the repository does not carry is only reported: the file it holds
# may come from a package of another name.
#
# The database is also the file whose absence a compile cannot survive.
# MiKTeX fetches it from a server when it is missing, and a job has no
# one to answer a server that does not reply.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/46

set -u

repo=${TEX_REPO:?TEX_REPO must name the folder of the repository.}
needs=tests/needs_results.txt

mkdir -p "$repo"

# The URL comes from MiKTeX, which keeps a list of repositories and picks
# one, so that no mirror is named here. The redirector of CTAN answers
# when it cannot.
url=$(mpm --pick-repository-url 2>/dev/null | tr -d '\r' | head -1)
case $url in
  http*) ;;
  *) url=https://mirror.ctan.org/systems/win32/miktex/tm/packages ;;
esac
url=${url%/}
echo "Repository: $url"

# FUNCTION: fetch one archive, and answer 1 when the repository has none
# of that name. An archive already fetched is left alone, because the
# closure below reaches a package by more than one route. A failed fetch
# leaves nothing behind, because a file of no bytes would read as an
# archive that the repository holds.
Fetch() {
  if [ -f "$repo/$1" ]; then
    return 0
  fi
  if curl -fsSL --retry 3 -o "$repo/$1" "$url/$1"; then
    return 0
  fi
  rm -f "$repo/$1"
  return 1
}

# The names of the database archives come from the repository's own
# index, because the suffix belongs to the layout and not to the version
# of MiKTeX: the index of a MiKTeX 26.5 repository still names them 2.9.
dbs=$(curl -fsSL --retry 3 "$url/" |
  grep -o 'miktex-zzdb[0-9]*-[0-9.]*\.tar\.lzma' | sort -u)
if [ -z "$dbs" ]; then
  echo "::error::$url names no miktex-zzdb archive, so the repository can hold no package database."
  exit 1
fi
for db in $dbs; do
  echo "Fetching the package database: $db"
  if ! Fetch "$db"; then
    echo "::error::$url holds no $db, which every package repository needs."
    exit 1
  fi
done

# The packages come from the list that warm-miktex.sh writes, which
# texcheck.vim reads from the templates, so a new class or package needs
# no change here. An entry names a file, and the archive of a package
# carries the name of the package, which is the name of the file for most
# of them and for none of the rest.
if [ ! -f "$needs" ]; then
  echo "::warning::$needs does not exist, so the repository holds the database alone. warm-miktex.sh writes that list."
else
  queue=$(sed 's/\.[^.]*$//' "$needs" | sort -u | tr '\n' ' ')
  seen=''
  while [ -n "${queue// /}" ]; do
    later=''
    for id in $queue; do
      case " $seen " in
        *" $id "*) continue ;;
      esac
      seen="$seen $id"
      # Without the message of curl, because a name that the repository
      # does not hold is the expected answer here and the line below
      # says so in words.
      if Fetch "$id.tar.lzma" 2>/dev/null; then
        echo "Fetched $id"
        # A package names the packages it needs, so the repository
        # carries those as well. Asking MiKTeX keeps the list in one
        # place, its own database.
        later="$later $(miktex packages info --template '{requiredPackages}' \
          "$id" 2>/dev/null | tr -d '\r' | tr ',;' '  ')"
      else
        echo "No archive is named $id, so another package holds that file."
      fi
    done
    queue=$later
  done
fi

# Prove that MiKTeX reads the directory as a repository before the entry
# is ever saved, because a directory that it refuses would restore and
# fail in the leg that a compile runs in.
if ! said=$(miktex packages update-package-database --repository "$repo" 2>&1); then
  printf '%s\n' "$said"
  echo "::error::MiKTeX refused $repo as a package repository. Everything it said is above."
  exit 1
fi
printf '%s\n' "$said"

echo "The repository holds:"
ls -l "$repo"
