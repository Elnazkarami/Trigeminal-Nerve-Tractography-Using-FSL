#!/usr/bin/env bash
# Fit the diffusion tensor to the corrected data (analysis branch A).
#
# This branch is independent of BEDPOSTX: bedpostx and probtrackx2 do not read
# any dtifit output. The tensor maps are used for QC (V1 orientation check) and
# for visual inspection of FA/MD.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") WORKDIR

Reads WORKDIR/diffusion/{data,bvals,bvecs,nodif_brain_mask} from 01_preprocess.sh
and writes WORKDIR/dti/dti_{FA,MD,L1,L2,L3,V1,V2,V3,MO,S0}.nii.gz.
EOF
}

[ "${1:-}" != "-h" ] || { usage; exit 0; }
[ $# -eq 1 ] || { usage >&2; die "Expected exactly one argument (WORKDIR)."; }
workdir=$1
in="$workdir/diffusion"

require_dir "$in" "preprocessed diffusion directory (run 01_preprocess.sh first)"
require_image "$in/data" "corrected DWI series"
require_file "$in/bvals" "b-values"
require_file "$in/bvecs" "rotated b-vectors"
require_image "$in/nodif_brain_mask" "brain mask"
require_fsl dtifit

mkdir -p "$workdir/dti"
record_provenance "$workdir" "$0" "$@"

dtifit -k "$in/data" \
  -o "$workdir/dti/dti" \
  -m "$in/nodif_brain_mask" \
  -r "$in/bvecs" \
  -b "$in/bvals"

log "Done. Check V1 orientation before trusting the gradient table (docs/qc.md, section 4):"
log "  fsleyes $workdir/dti/dti_FA $workdir/dti/dti_V1 -ot rgbvector"
