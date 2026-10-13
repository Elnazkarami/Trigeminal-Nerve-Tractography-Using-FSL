#!/usr/bin/env bash
# Estimate fibre orientation distributions with BEDPOSTX (analysis branch B).
#
# BEDPOSTX reads the corrected data, bvals, rotated bvecs and mask from
# WORKDIR/diffusion directly; it does not use the dtifit output.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") WORKDIR [bedpostx options]

Runs bedpostx on WORKDIR/diffusion. The output directory is always
WORKDIR/diffusion.bedpostX, which 04_tractography.sh reads.
Any extra arguments (e.g. -n 3) are passed to bedpostx unchanged.
EOF
}

[ "${1:-}" != "-h" ] || { usage; exit 0; }
[ $# -ge 1 ] || { usage >&2; die "Expected WORKDIR as the first argument."; }
workdir=$1
shift
in="$workdir/diffusion"
bpx="$workdir/diffusion.bedpostX"

require_dir "$in" "preprocessed diffusion directory (run 01_preprocess.sh first)"
require_image "$in/data" "corrected DWI series"
require_file "$in/bvals" "b-values"
require_file "$in/bvecs" "rotated b-vectors"
require_image "$in/nodif_brain_mask" "brain mask"
require_fsl bedpostx bedpostx_datacheck
[ ! -e "$bpx" ] || die "$bpx already exists; remove it to rerun BEDPOSTX."

record_provenance "$workdir" "$0" "$workdir" "$@"
bedpostx_datacheck "$in"
bedpostx "$in" "$@"

# On a cluster (fsl_sub), bedpostx submits jobs and returns before they finish.
log "BEDPOSTX output directory: $bpx"
log "Check that $bpx/merged_th1samples.nii.gz exists before running 04_tractography.sh."
