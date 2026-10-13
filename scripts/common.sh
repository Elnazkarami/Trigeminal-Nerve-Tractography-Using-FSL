# shellcheck shell=bash
# Shared helpers sourced by the numbered pipeline scripts. Not meant to be run directly.

log() { printf '[%s] %s\n' "$(basename "$0")" "$*" >&2; }

die() {
  printf '[%s] ERROR: %s\n' "$(basename "$0")" "$*" >&2
  exit 1
}

# Abort unless FSL is configured and every named command is on PATH.
require_fsl() {
  [ -n "${FSLDIR:-}" ] || die "FSLDIR is not set. Install FSL and source \$FSLDIR/etc/fslconf/fsl.sh first."
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required FSL command '$cmd' was not found on PATH."
  done
}

require_file() {
  [ -f "$1" ] || die "Missing ${2:-file}: $1"
}

require_dir() {
  [ -d "$1" ] || die "Missing ${2:-directory}: $1"
}

# FSL accepts image names with or without the .nii/.nii.gz extension.
require_image() {
  local ext
  for ext in "" .nii.gz .nii; do
    [ -f "$1$ext" ] && return 0
  done
  die "Missing ${2:-image}: $1 (looked for $1, $1.nii.gz, $1.nii)"
}

# Print an absolute path for an existing file (list files passed to probtrackx2 need these).
abspath() {
  (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd)" "$(basename "$1")")
}

# Succeed when two images have the same matrix size and voxel dimensions.
same_grid() {
  local key a b
  for key in dim1 dim2 dim3 pixdim1 pixdim2 pixdim3; do
    a=$(fslval "$1" "$key" | tr -d ' ')
    b=$(fslval "$2" "$key" | tr -d ' ')
    [ "$a" = "$b" ] || return 1
  done
}

# Append the FSL version and the exact command line to WORKDIR/provenance.log.
record_provenance() {
  local workdir=$1
  shift
  local version
  version=$(cat "$FSLDIR/etc/fslversion" 2>/dev/null || echo unknown)
  mkdir -p "$workdir"
  printf '%s\tFSL %s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$version" "$*" >> "$workdir/provenance.log"
}
