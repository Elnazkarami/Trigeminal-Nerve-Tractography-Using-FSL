#!/usr/bin/env bash
# Correct the raw DWI series for eddy currents and head motion, rotate the
# b-vectors to match, and build the single diffusion-space brain mask used by
# every later step.
#
# HISTORICAL WORKFLOW: this uses eddy_correct (affine registration of each
# volume to one b=0 reference) followed by fdt_rotate_bvecs. eddy_correct is
# deprecated in current FSL in favour of eddy. It is kept here because it is
# the workflow this project used; see README.md ("Preprocessing") for what an
# eddy-based replacement would need.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") -i DWI -b BVALS -r BVECS -o WORKDIR [options]

Required:
  -i DWI       Raw 4D diffusion series (NIfTI)
  -b BVALS     b-values in FSL format (one row, one value per volume)
  -r BVECS     b-vectors in FSL format (three rows, one column per volume)
  -o WORKDIR   Subject working directory (created if needed)

Options:
  -t THRESH    Largest b-value treated as b=0 (default: 50)
  -f FRAC      BET fractional intensity threshold (default: 0.3)
  -M MASK      Use this checked/edited brain mask instead of running BET.
               It must be on the grid of the raw DWI series.
  -h           Show this help

Outputs in WORKDIR/diffusion/ (laid out as a BEDPOSTX input directory):
  data.nii.gz              corrected DWI series
  data.ecclog              eddy_correct registration log
  bvals                    copy of the input b-values
  bvecs                    b-vectors rotated with the eddy_correct transforms
  bvecs_original           unrotated input b-vectors (kept for reference only)
  reference_volume.txt     0-based index of the b=0 reference volume
  nodif.nii.gz             reference b=0 volume taken from the corrected series
  nodif_brain_mask.nii.gz  brain mask used by dtifit, bedpostx and probtrackx2
EOF
}

dwi="" bvals="" bvecs="" workdir="" b0_thr=50 frac=0.3 mask_in=""
while getopts "i:b:r:o:t:f:M:h" opt; do
  case $opt in
    i) dwi=$OPTARG ;;
    b) bvals=$OPTARG ;;
    r) bvecs=$OPTARG ;;
    o) workdir=$OPTARG ;;
    t) b0_thr=$OPTARG ;;
    f) frac=$OPTARG ;;
    M) mask_in=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

if [ -z "$dwi" ] || [ -z "$bvals" ] || [ -z "$bvecs" ] || [ -z "$workdir" ]; then
  usage >&2
  die "-i, -b, -r and -o are all required."
fi

require_image "$dwi" "DWI series"
require_file "$bvals" "b-values file"
require_file "$bvecs" "b-vectors file"
[ -z "$mask_in" ] || require_image "$mask_in" "brain mask"
require_fsl fslval fslroi fslmaths eddy_correct fdt_rotate_bvecs bet

out="$workdir/diffusion"
[ ! -e "$out/data.ecclog" ] || die "$out/data.ecclog already exists; remove $out or choose a new WORKDIR."

# Check that the gradient table matches the image before anything is run.
nvols=$(fslval "$dwi" dim4 | tr -d ' ')
nbvals=$(awk '{ n += NF } END { print n + 0 }' "$bvals")
[ "$nbvals" -eq "$nvols" ] || die "$bvals has $nbvals values but $dwi has $nvols volumes."
nrows=$(awk 'NF > 0 { r++ } END { print r + 0 }' "$bvecs")
[ "$nrows" -eq 3 ] || die "$bvecs has $nrows rows; FSL format needs 3 rows (transpose an N x 3 file first)."
awk -v n="$nvols" 'NF > 0 && NF != n { bad = 1 } END { exit bad }' "$bvecs" \
  || die "Every row of $bvecs must have $nvols entries."

# The reference is the first volume with b <= threshold, not blindly volume 0.
b0_list=$(awk -v t="$b0_thr" '{ for (i = 1; i <= NF; i++) { if ($i <= t) printf "%d ", c; c++ } }' "$bvals")
[ -n "$b0_list" ] || die "No volume has b <= $b0_thr in $bvals; cannot choose a b=0 reference."
ref=${b0_list%% *}
log "b=0 volumes (0-based, b <= $b0_thr): $b0_list"
log "Reference volume for eddy_correct and the mask: $ref"

if [ -n "$mask_in" ]; then
  same_grid "$mask_in" "$dwi" || die "$mask_in is not on the same voxel grid as $dwi."
fi

mkdir -p "$out"
record_provenance "$workdir" "$0" "$@"
cp "$bvals" "$out/bvals"
cp "$bvecs" "$out/bvecs_original"
printf '%s\n' "$ref" > "$out/reference_volume.txt"

log "Running eddy_correct (this registers every volume to volume $ref)"
eddy_correct "$dwi" "$out/data" "$ref"

# Each volume was rotated during registration, so its gradient must be rotated too.
# Downstream steps read $out/bvecs (rotated); bvecs_original is never used again.
log "Rotating b-vectors with the eddy_correct transforms"
fdt_rotate_bvecs "$out/bvecs_original" "$out/bvecs" "$out/data.ecclog"

fslroi "$out/data" "$out/nodif" "$ref" 1

# One mask for the whole pipeline: BET on the corrected reference b=0, or a
# supplied mask that was edited to keep skull-base anatomy (docs/roi_protocol.md).
if [ -n "$mask_in" ]; then
  log "Using supplied mask $mask_in"
  fslmaths "$mask_in" -bin "$out/nodif_brain_mask" -odt char
  fslmaths "$out/nodif" -mas "$out/nodif_brain_mask" "$out/nodif_brain"
else
  log "Running BET on the reference b=0 (f=$frac)"
  bet "$out/nodif" "$out/nodif_brain" -m -f "$frac"
fi

log "Done. Inspect the mask before continuing (docs/qc.md, section 3):"
log "  fsleyes $out/nodif $out/nodif_brain_mask -cm red -a 40"
