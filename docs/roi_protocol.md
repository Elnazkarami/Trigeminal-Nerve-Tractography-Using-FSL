# ROI protocol: trigeminal nerve (CN V)

This document describes how the regions of interest for trigeminal tractography are
defined. It is the part of the pipeline that makes this a *trigeminal* project and not
a generic FSL tutorial. Everything else in `scripts/` is standard FDT usage.

> **Status.** Sections marked **TODO (author)** must be completed with the protocol
> that was actually used. The *Guidance* notes explain what each decision involves and
> list common choices from the literature. They are **not** a record of what was done.

---

## 1. Target structure

**TODO (author):** state the exact segment reconstructed, for example:

- the **cisternal segment** of CN V, from the root entry zone (REZ) at the lateral pons
  to the porus trigeminus / entrance of Meckel's cave; or
- the cisternal segment **plus** the intra-pontine trigeminal tract to the principal
  sensory / spinal trigeminal nuclei; or
- something else (state it).

*Guidance.* The cisternal segment is short (roughly 1 cm) and only a few voxels wide at
typical DWI resolution (around 2 mm isotropic). Partial-volume effects with CSF and the
adjacent middle cerebellar peduncle (MCP) are the main sources of error. Peripheral
branches (V1/V2/V3) distal to the Gasserian ganglion are generally not reliably
reconstructed from standard brain DWI and should not be claimed without
dedicated acquisitions.

## 2. Image used to identify anatomy and draw each ROI

| ROI | Drawn on | Space of that image |
|-----|----------|---------------------|
| Seed | **TODO (author)** e.g. colour-coded FA (`dti_FA` + `dti_V1`), b=0 | diffusion |
| Waypoint / target | **TODO (author)** | **TODO** |
| Exclusion | **TODO (author)** | **TODO** |

*Guidance.* The nerve is usually easiest to see on a heavily T2-weighted 3D sequence
(e.g. CISS/FIESTA/SPACE) if one was acquired, where it shows up dark against bright CSF. On
diffusion data alone, the b=0 image (nerve dark against bright CSF) and the
direction-encoded colour FA map (nerve anterior-posterior/oblique, MCP different
orientation) are used together. State the viewer and its version (FSLeyes x.y).

## 3. Left / right handling

**TODO (author):** confirm the following, or describe your own approach.

- Left and right nerves are reconstructed in **separate runs** with separate seed,
  waypoint and exclusion masks (`-l CNV_left`, `-l CNV_right`).
- A **mid-sagittal exclusion plane** is used in each run so streamlines cannot cross to the
  contralateral side.
- Side was confirmed from the image orientation, not the viewer's display. FSLeyes
  shows L/R labels from the header. Check `fslhd nodif | grep -E 'qform_code|sform_code|_orient'`
  before drawing.

## 4. ROI definitions

**TODO (author):** fill in the definition you used for each row, and delete rows you did not use.

| Role | `04_tractography.sh` flag | Definition (anatomy, slices, size) | Guidance: common choice |
|------|---------------------------|-------------------------------------|---------------------------|
| Seed | `-x` | **TODO** | Cisternal CN V at or just anterior to the REZ on axial slices through the mid-pons |
| Waypoint | `-W` | **TODO** | Coronal/axial ROI at the porus trigeminus / Meckel's cave entrance |
| Target | `-t` | **TODO** | Only if seed-to-target counts are reported. Otherwise omit |
| Exclusion | `-a` | **TODO** | Mid-sagittal plane, MCP/cerebellum, ipsilateral temporal lobe above the tentorium |
| Termination | `-T` | **TODO** | Optional, e.g. stop at Meckel's cave if only the cisternal segment is wanted |

Notes on the defaults built into `04_tractography.sh`:

- Several `-W` masks are combined with `--waycond=AND`: a streamline must cross all of them.
- `--onewaycondition` applies the waypoint condition to each half of a bidirectional
  streamline separately. With a seed at one end of the segment, this keeps only
  streamlines that leave the seed in the direction of the waypoint.
- `-l` (loop check) is enabled. Curvature threshold, step length, and number of samples
  stay at probtrackx2 defaults unless they are passed after `--`. **TODO (author):** record any
  non-default values you used.

## 5. Bringing masks into tracking space

Two cases are supported, and the script never invents a transform:

**(a) Masks drawn directly in diffusion space** (on `nodif`, `dti_FA` or `dti_V1`).
This is the default. No `--xfm`/`--invxfm` is needed and none is passed.
`04_tractography.sh` checks that every mask is on the grid of
`diffusion.bedpostX/nodif_brain_mask`.

**(b) Masks drawn on another image** (e.g. a structural T2). The transform has to be
created and checked first. For a rigid/affine registration:

```bash
# Register the diffusion reference b=0 to the structural image (diffusion -> structural)
flirt -in WORKDIR/diffusion/nodif_brain -ref T2_brain -dof 6 -omat diff2str.mat
# Invert it: structural (seed) space -> diffusion space, which is what --xfm expects
convert_xfm -omat str2diff.mat -inverse diff2str.mat
```

```bash
scripts/04_tractography.sh -w WORKDIR -l CNV_left -x seed_T2space.nii.gz \
  -X str2diff.mat -R T2_brain.nii.gz ...
```

Direction convention (from the probtrackx2 documentation): `--xfm` goes **from seed space
to diffusion space**. `--invxfm` goes from diffusion space to seed space and is
needed only when `--xfm` is a nonlinear warp field. In case (b), every mask (seed,
waypoints, targets, exclusion) must be in seed space.

**TODO (author):** state which case you used. If (b), give the registration cost function,
degrees of freedom, and how the registration was checked at the skull base.

## 6. Mask coverage (critical for CN V)

probtrackx2 terminates a streamline as soon as it leaves the mask given with `-m`
(here `diffusion.bedpostX/nodif_brain_mask`, copied from the preprocessing mask), and
BEDPOSTX does not estimate fibre orientations outside it. The cisternal trigeminal
nerve and Meckel's cave sit at the skull base, next to the petrous apex. **BET on a
b=0 image frequently cuts this region away**, especially where susceptibility distortion is strong.

Required checks:

1. Overlay the mask on `nodif` and confirm it includes the pons, the prepontine
   cistern containing CN V on both sides, and the entrance to Meckel's cave.
2. If it does not, edit the mask (FSLeyes edit mode, or dilate locally), save it on the
   DWI grid, and rerun preprocessing with `scripts/01_preprocess.sh ... -M edited_mask.nii.gz`.
   This mask then feeds dtifit, BEDPOSTX and probtrackx2 consistently.
3. `04_tractography.sh` reports how many seed/waypoint/target voxels lie outside the
   BEDPOSTX mask. Treat any warning as a protocol failure for that ROI.

**TODO (author):** state whether the BET mask was sufficient or edited, and the BET `-f` used.

## 7. Acceptance and rejection of a reconstruction

See [qc.md](qc.md#7-tractography), section 7, for the checklist. **TODO (author):** give
the criteria you applied, for example the minimum `waytotal`, the display threshold, and
which anatomical deviations led to rejection.

## 8. Reference protocol

**TODO (author):** cite the publication(s) or lab protocol whose ROI placement was
followed, and note any deviations. If the protocol was developed in-house, say so and give
the date or version.
