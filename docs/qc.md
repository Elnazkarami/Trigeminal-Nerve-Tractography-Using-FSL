# Quality control and rejection criteria

Checks are listed in pipeline order. **Automated** checks are performed by the scripts
and stop the run with an error. **Visual** checks must be done by a person.
Thresholds marked **TODO (author)** should state the values actually applied. They are
deliberately not filled in with made-up numbers.

Record each subject in the [QC log](#qc-log-template) at the end.

## 1. Inputs and gradient table (`01_preprocess.sh`)

Automated:
- number of b-values equals the number of volumes
- `bvecs` has 3 rows with one column per volume
- at least one volume with b ≤ threshold (default 50 s/mm²) exists. The **first** such
  volume becomes the reference, and its index is written to `diffusion/reference_volume.txt`.

Visual:
- [ ] The reference volume really is a b=0 image (bright CSF, no diffusion contrast).
- [ ] No volume is grossly corrupted (signal dropout, severe slice-wise artefact) on a
      movie-mode pass through the raw series.

Reject or exclude volumes if: **TODO (author)**

## 2. Eddy-current and motion correction (`01_preprocess.sh`)

`eddy_correct` is the historical FSL tool used in this project. The corresponding rotated
gradients are written to `diffusion/bvecs` by `fdt_rotate_bvecs`, and only that file is
used downstream.

Visual:
- [ ] Corrected series (`diffusion/data`) is stable in movie mode, with no residual jumps
      between volumes.
- [ ] Estimated motion from `diffusion/data.ecclog` is within the tolerance below.

Reject the subject if: **TODO (author)**, e.g. maximum displacement above a set fraction
of voxel size.

## 3. Brain mask (`01_preprocess.sh`)

One mask is made: BET on the corrected reference b=0 (`-f 0.3` by default), or a
supplied mask via `-M`. That same file is used by dtifit, BEDPOSTX and probtrackx2.

Visual (`fsleyes diffusion/nodif diffusion/nodif_brain_mask -cm red -a 40`):
- [ ] Mask includes the pons and both prepontine trigeminal nerves.
- [ ] Mask includes the porus trigeminus / entrance to Meckel's cave on both sides.
- [ ] Mask does not include large amounts of extra-cranial tissue.

If the skull-base anatomy is cut off, edit the mask and rerun with `-M`
([roi_protocol.md §6](roi_protocol.md#6-mask-coverage-critical-for-cn-v)).

## 4. Tensor fit (`02_fit_tensor.sh`)

Visual (`fsleyes dti/dti_FA dti/dti_V1 -ot rgbvector`):
- [ ] FA lies in [0, 1] and looks anatomically plausible.
- [ ] **Gradient orientation check:** V1 is left-right in the corpus callosum genu/splenium,
      superior-inferior in the corticospinal tract, and anterior-posterior in the
      cingulum. A systematic flip means the bvecs sign or axis convention is wrong. Fix this
      before running BEDPOSTX.

## 5. BEDPOSTX (`03_bedpostx.sh`)

Automated: `bedpostx_datacheck` runs before `bedpostx`.

Visual:
- [ ] `diffusion.bedpostX/dyads1` shows plausible orientations in major tracts and in
      the trigeminal region.
- [ ] `mean_f1samples` is non-zero along the cisternal nerve. If it is near zero there,
      tractography through the segment is unreliable.

## 6. ROIs (`04_tractography.sh`)

Automated:
- all masks exist and are on the same grid (diffusion space, or seed space with `-X`)
- seed is non-empty and overlaps the BEDPOSTX mask
- a warning is printed for any seed/waypoint/target voxel outside the BEDPOSTX mask

Visual:
- [ ] Each ROI is on the intended side (check header orientation, not only the viewer).
- [ ] Each ROI matches its definition in [roi_protocol.md §4](roi_protocol.md#4-roi-definitions).

## 7. Tractography

Outputs: `fdt_paths` is the number of samples passing through each voxel. `waytotal` is
the number of samples accepted after the waypoint and exclusion criteria.
`fdt_paths_norm` is `fdt_paths / waytotal`. These are **streamline-count / density**
maps. They are not a direct measure of anatomical connection strength, axon count or
nerve integrity.

Visual (`fsleyes dti/dti_FA tract/CNV_left/fdt_paths_norm -cm hot -dr <thr> <max>`):
- [ ] The reconstruction runs from the seed to the waypoint along the expected course of
      the nerve.
- [ ] No substantial leakage into the MCP, cerebellum, contralateral side or
      supratentorial tissue.

Reject a reconstruction if:
- `waytotal` is 0 (the script warns), or below **TODO (author)**
- **TODO (author)**: anatomical deviation criteria
- Display threshold used for figures and judgement: **TODO (author)**, e.g. a fixed fraction
  of `waytotal` on `fdt_paths_norm`

## QC log template

| Subject | Ref vol | Mask edited? | V1 check | Side | waytotal | Accepted? | Rater | Notes |
|---------|---------|--------------|----------|------|----------|-----------|-------|-------|
| sub-01  |         |              |          | L    |          |           |       |       |
| sub-01  |         |              |          | R    |          |           |       |       |
