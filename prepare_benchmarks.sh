#!/usr/bin/env bash
# Prepare a stripped copy of HeCBench (branch ktwork, src2/) for agent optimisation:
# keep only the *-omp benchmarks, rename them without the -omp suffix, remove all
# OpenMP pragmas (including backslash-continued ones), and drop everything else
# (other variants, top-level files, .git and all other hidden files).
# The local HeCBench clone (if any) is deleted afterwards so agents cannot peek at it.
set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
LOCAL_CLONE="$HERE/HeCBench"
UPSTREAM="https://github.com/RIKEN-RCCS/HeCBench.git"
SRC_REPO="${1:-$([[ -d "$LOCAL_CLONE" ]] && echo "$LOCAL_CLONE" || echo "$UPSTREAM")}"
DEST="${2:-$HERE/benchmarks}"
BRANCH="ktwork"
KEEP_SHARED=(include lib data)

# Works whether the source clone has a local "$BRANCH" or only "origin/$BRANCH".
clone_branch() {
  rm -rf "$DEST"
  git clone --quiet --no-checkout "$SRC_REPO" "$DEST"
  git -C "$DEST" fetch --quiet origin "+refs/remotes/origin/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null || true
  git -C "$DEST" checkout --quiet "origin/$BRANCH" 2>/dev/null || git -C "$DEST" checkout --quiet "$BRANCH"
}

keep_only_omp_benchmarks() {
  local dir name
  for dir in "$DEST"/src2/*/; do
    name=$(basename "$dir")
    if [[ "$name" == *-omp ]]; then
      mv "$dir" "$DEST/src2/${name%-omp}"
    elif [[ ! " ${KEEP_SHARED[*]} " == *" $name "* ]]; then
      rm -rf "$dir"
    fi
  done
}

source_files() {
  find "$DEST/src2" -type f \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' \
      -o -name '*.cxx' -o -name '*.h' -o -name '*.hpp' -o -name '*.cu' \) "$@"
}

# Some sources have CRLF line endings, which would hide backslash continuations.
normalise_line_endings() {
  source_files -exec sed -i 's/\r$//' {} +
}

# Deletes "#pragma omp ..." lines (also commented-out ones) with their backslash-continued lines.
strip_omp_pragmas() {
  source_files -exec sed -i '/^[[:space:]]*\(\/\/[[:space:]]*\)\?#[[:space:]]*pragma[[:space:]]\+omp\b/{:a;/\\$/{N;ba};d}' {} +
}

# Makefiles reference headers from sibling variants (e.g. -I../foo-cuda for
# reference.h). Copy the headers a benchmark #includes from those siblings into
# the benchmark itself and point the Makefiles at the local copies.
sibling_dirs_of() {
  grep -ho -- '\.\./[A-Za-z0-9_+.-]*-\(cuda\|sycl\|hip\|acc\)' "$1"/Makefile* 2>/dev/null | sort -u
}

included_headers() {
  grep -ho '#[[:space:]]*include[[:space:]]*"[^"]*"' "$1"/*.c* "$1"/*.h* 2>/dev/null \
    | sed 's/.*"\(.*\)"/\1/' | sort -u || true
}

copy_included_headers() {
  local bench="$1" sibling="$2" pass header
  for pass in 1 2 3; do
    for header in $(included_headers "$bench"); do
      if [[ ! -e "$bench/$header" && -e "$sibling/$header" ]]; then
        mkdir -p "$(dirname "$bench/$header")" && cp "$sibling/$header" "$bench/$header"
      fi
    done
  done
}

localise_sibling_headers() {
  local bench sibling pattern
  for bench in "$DEST"/src2/*-omp/; do
    for sibling in $(sibling_dirs_of "$bench"); do
      copy_included_headers "$bench" "$bench/$sibling"
      pattern=$(printf '%s' "$sibling" | sed 's/[.]/\\./g')
      sed -i -e "s|-I$pattern/\?||g" -e "s|$pattern/|./|g" "$bench"/Makefile*
    done
  done
}

flatten_and_clean() {
  find "$DEST" -mindepth 1 -maxdepth 1 ! -name src2 -exec rm -rf {} +
  rm -f "$DEST/src2/CMakeLists.txt"
  mv "$DEST"/src2/* "$DEST"/
  rmdir "$DEST/src2"
  find "$DEST" -name '.*' -exec rm -rf {} + 2>/dev/null || true
}

remove_local_clone() {
  [[ -d "$LOCAL_CLONE" ]] && rm -rf "$LOCAL_CLONE"
}

clone_branch
localise_sibling_headers
keep_only_omp_benchmarks
normalise_line_endings
strip_omp_pragmas
flatten_and_clean
remove_local_clone
echo "Prepared $(find "$DEST" -mindepth 1 -maxdepth 1 -type d | wc -l) directories in $DEST"
