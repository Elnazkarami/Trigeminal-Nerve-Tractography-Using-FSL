#!/usr/bin/env bash
# Run probtrackx2 from a supplied seed ROI, for one side at a time.
#
# By default all masks must already be in diffusion space (the grid of
# WORKDIR/diffusion/nodif), and no transform is passed to probtrackx2. Only
# when masks were drawn in another space (e.g. a structural T2) are -X/-I/-R
# needed; see docs/roi_protocol.md ("Bringing masks into tracking space").
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") -w WORKDIR -l LABEL -x SEED [options] [-- probtrackx2 options]

Required:
  -w WORKDIR   Subject working directory (must contain diffusion.bedpostX)
  -l LABEL     Name of this run, e.g. CNV_left; output goes to WORKDIR/tract/LABEL
  -x SEED      Seed mask

Optional ROIs (see docs/roi_protocol.md for their definitions):
  -W MASK      Waypoint mask; repeat for several (a streamline must cross all)
  -t MASK      Target mask for seed-to-target counts; repeat for several
  -a MASK      Exclusion mask (streamlines entering it are discarded)
  -T MASK      Termination mask (streamlines stop on entering it)

Options:
  -n N         Samples per seed voxel (default: 5000)
  -X XFM       Only for masks NOT in diffusion space: transform from mask
               (seed) space to diffusion space (FLIRT matrix or FNIRT warp)
  -I INVXFM    Inverse transform, diffusion space to seed space (required by
               probtrackx2 when -X is a warp field)
  -R REF       Reference image defining seed space (default: the seed mask)
  -h           Show this help

Arguments after -- are passed to probtrackx2 unchanged.
EOF
}

orig_args=("$@")
workdir="" label="" seed="" avoid="" stop="" xfm="" invxfm="" seedref="" nsamples=5000
waypoints=()
targets=()
while getopts "w:l:x:W:t:a:T:n:X:I:R:h" opt; do
  case $opt in
    w) workdir=$OPTARG ;;
    l) label=$OPTARG ;;
    x) seed=$OPTARG ;;
    W) waypoints+=("$OPTARG") ;;
    t) targets+=("$OPTARG") ;;
    a) avoid=$OPTARG ;;
    T) stop=$OPTARG ;;
    n) nsamples=$OPTARG ;;
    X) xfm=$OPTARG ;;
    I) invxfm=$OPTARG ;;
    R) seedref=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [ -z "$workdir" ] || [ -z "$label" ] || [ -z "$seed" ]; then
  usage >&2
  die "-w, -l and -x are all required."
fi
[ -z "$invxfm" ] || [ -n "$xfm" ] || die "-I was given without -X."
[ -z "$seedref" ] || [ -n "$xfm" ] || die "-R is only meaningful together with -X."

bpx="$workdir/diffusion.bedpostX"
out="$workdir/tract/$label"

require_dir "$bpx" "BEDPOSTX directory (run 03_bedpostx.sh first)"
require_image "$bpx/merged_th1samples" "BEDPOSTX samples (has bedpostx finished?)"
require_image "$bpx/nodif_brain_mask" "BEDPOSTX mask"
require_image "$seed" "seed mask"
for m in ${waypoints[@]+"${waypoints[@]}"} ${targets[@]+"${targets[@]}"}; do
  require_image "$m" "waypoint/target mask"
done
[ -z "$avoid" ] || require_image "$avoid" "exclusion mask"
[ -z "$stop" ] || require_image "$stop" "termination mask"
[ -z "$xfm" ] || require_file "$xfm" "seed-to-diffusion transform"
[ -z "$invxfm" ] || require_image "$invxfm" "diffusion-to-seed transform"
[ -z "$seedref" ] || require_image "$seedref" "seed-space reference"
require_fsl probtrackx2 fslval fslstats fslmaths

# All masks given, and the subset that streamlines must actually reach.
reach_masks=("$seed" ${waypoints[@]+"${waypoints[@]}"} ${targets[@]+"${targets[@]}"})
all_masks=("${reach_masks[@]}")
[ -z "$avoid" ] || all_masks+=("$avoid")
[ -z "$stop" ] || all_masks+=("$stop")

# Every ROI must share one grid: diffusion space by default, seed space with -X.
grid_ref="$bpx/nodif_brain_mask"
[ -z "$xfm" ] || grid_ref=${seedref:-$seed}
for m in "${all_masks[@]}"; do
  same_grid "$m" "$grid_ref" || die "$m is not on the grid of $grid_ref. Resample/register it first (docs/roi_protocol.md)."
done

# probtrackx2 stops a streamline when it leaves the BEDPOSTX mask, so seed,
# waypoint and target voxels outside that mask can never be reached.
# This check is only possible when the ROIs are in diffusion space.
if [ -z "$xfm" ]; then
  for m in "${reach_masks[@]}"; do
    total=$(fslstats "$m" -V | awk '{ print $1 }')
    inside=$(fslstats "$m" -k "$bpx/nodif_brain_mask" -V | awk '{ print $1 }')
    [ "$total" -gt 0 ] || die "$m is empty."
    [ "$inside" -gt 0 ] || die "$m lies entirely outside the BEDPOSTX mask; no streamline can reach it."
    [ "$inside" -eq "$total" ] \
      || log "WARNING: $((total - inside)) of $total voxels of $m are outside the BEDPOSTX mask (docs/roi_protocol.md, 'Mask coverage')."
  done
fi

mkdir -p "$out"
record_provenance "$workdir" "$0" "${orig_args[@]}"

args=(
  -x "$seed"
  -s "$bpx/merged"
  -m "$bpx/nodif_brain_mask"
  --dir="$out"
  --forcedir
  --opd
  -l
  --onewaycondition
  -P "$nsamples"
)

if [ ${#waypoints[@]} -gt 0 ]; then
  : > "$out/waypoints.txt"
  for m in "${waypoints[@]}"; do abspath "$m" >> "$out/waypoints.txt"; done
  args+=(--waypoints="$out/waypoints.txt" --waycond=AND)
fi
if [ ${#targets[@]} -gt 0 ]; then
  : > "$out/targets.txt"
  for m in "${targets[@]}"; do abspath "$m" >> "$out/targets.txt"; done
  args+=(--targetmasks="$out/targets.txt" --os2t --s2tastext)
fi
[ -z "$avoid" ] || args+=(--avoid="$avoid")
[ -z "$stop" ] || args+=(--stop="$stop")
if [ -n "$xfm" ]; then
  args+=(--xfm="$xfm" --seedref="${seedref:-$seed}")
  [ -z "$invxfm" ] || args+=(--invxfm="$invxfm")
fi

log "probtrackx2 ${args[*]} $*"
probtrackx2 "${args[@]}" "$@"

# fdt_paths counts the samples passing through each voxel; dividing by waytotal
# (number of accepted samples) gives a run-size-independent map for display.
require_file "$out/waytotal" "probtrackx2 waytotal output"
waytotal=$(awk 'NR == 1 { print $1 + 0 }' "$out/waytotal")
if [ "$waytotal" -gt 0 ]; then
  fslmaths "$out/fdt_paths" -div "$waytotal" "$out/fdt_paths_norm"
  log "Accepted samples (waytotal): $waytotal; wrote $out/fdt_paths_norm"
else
  log "WARNING: waytotal is 0 - no streamline satisfied the ROI conditions. Reject this run (docs/qc.md)."
fi
