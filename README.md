# Trigeminal Nerve Tractography Using FSL

Bash scripts and documentation for probabilistic tractography of the trigeminal nerve
(cranial nerve V) from diffusion MRI, using FSL's FDT tools (`eddy_correct`, `dtifit`,
`bedpostx`, `probtrackx2`).

## What this repository is (and is not)

**Research motivation.** Trigeminal tractography is used in studies of chronic orofacial
pain, such as trigeminal neuralgia and painful temporomandibular disorders, to look at
the structure of the nerve's cisternal segment. That clinical question motivated this
work.

**What the repository demonstrates.** A documented, single-subject processing pipeline:
diffusion preprocessing, a tensor fit, BEDPOSTX, and probtrackx2 seeded from
user-supplied ROIs. It contains **no imaging data, no masks, no group results and no
clinical findings.** Nothing here should be read as evidence about orofacial pain.

**Origin of the scripts.** **TODO (author):** choose one and edit:
- *Original research scripts:* cleaned-up versions of the commands used in
  [project / lab, years].
- *Reconstructed examples:* rewritten from memory or notes of a research workflow, not
  the exact files that were run.
- *Tutorial:* written to illustrate the method.

In their current form the scripts were reorganised from earlier command snippets in this
repository (see the git history). They have **not** been run on real data in this form.
See [Verification status](#verification-status).

### My contribution

**TODO (author):** one short paragraph describing what you personally did, for example:
"I preprocessed the diffusion data for N participants, drew the trigeminal seed and
exclusion ROIs on …, ran BEDPOSTX and probtrackx2, performed visual QC of every
reconstruction, and …". Delete anything that does not apply, such as acquisition,
ROI protocol design or statistical analysis.

### Data and masks

**TODO (author):** state whether the original data and ROI masks can be shared, and
why. For example: "The data were acquired under [ethics approval / data-use agreement]
and cannot be redistributed. Masks are derived from participant images and are not
shared." No data or masks are included in this repository.

## Repository contents

| Path | Purpose |
|------|---------|
| [scripts/01_preprocess.sh](scripts/01_preprocess.sh) | b=0 reference selection, `eddy_correct`, b-vector rotation, single brain mask |
| [scripts/02_fit_tensor.sh](scripts/02_fit_tensor.sh) | `dtifit` tensor maps (FA, MD, L1–L3, V1–V3) |
| [scripts/03_bedpostx.sh](scripts/03_bedpostx.sh) | `bedpostx` fibre orientation estimation |
| [scripts/04_tractography.sh](scripts/04_tractography.sh) | `probtrackx2` from supplied seed/waypoint/exclusion ROIs |
| [scripts/common.sh](scripts/common.sh) | Shared input/FSL checks and provenance logging |
| [docs/roi_protocol.md](docs/roi_protocol.md) | Anatomical ROI definitions for CN V, mask space, mask coverage |
| [docs/qc.md](docs/qc.md) | QC checks and rejection criteria at each step, QC log template |
| [LICENSE](LICENSE) | MIT licence for the code |
| `bedpostx`, `diffusion tensor model`, `preprocessing images` | Legacy snippets superseded by `scripts/`. To be removed |

## Requirements

- FSL with FDT (`eddy_correct`, `fdt_rotate_bvecs`, `bet`, `dtifit`, `bedpostx`,
  `probtrackx2`). Version used for the original analysis: **TODO (author)**.
  Each script appends the FSL version it finds (`$FSLDIR/etc/fslversion`) to
  `WORKDIR/provenance.log`.
- Bash 3.2 or later on Linux or macOS
- FSLeyes for ROI drawing and QC

Each script stops with a clear error if `FSLDIR` is unset, a required FSL command is
missing, or an expected input file does not exist.

## Pipeline

```
01_preprocess ──┬──> 02_fit_tensor                    branch A: tensor maps (QC, FA/MD inspection)
                └──> 03_bedpostx ──> 04_tractography  branch B: probabilistic tractography
```

The two branches are **independent**. BEDPOSTX reads the preprocessed data directly and
does not use any `dtifit` output. Branch A is still needed for the gradient orientation
check in [docs/qc.md](docs/qc.md) and for drawing ROIs on the colour FA map.

All scripts use one working directory per subject:

```
WORKDIR/
├── provenance.log            date, FSL version and command line of every step
├── diffusion/                written by 01, BEDPOSTX input directory
│   ├── data.nii.gz           corrected DWI series
│   ├── bvals
│   ├── bvecs                 rotated b-vectors (the only bvecs used downstream)
│   ├── bvecs_original
│   ├── data.ecclog
│   ├── reference_volume.txt
│   ├── nodif.nii.gz
│   └── nodif_brain_mask.nii.gz
├── dti/dti_*.nii.gz          written by 02
├── diffusion.bedpostX/       written by 03 (bedpostx names it from its input)
└── tract/<LABEL>/            written by 04, one directory per run/side
```

### 1. Preprocessing

```bash
scripts/01_preprocess.sh -i raw/dwi.nii.gz -b raw/bvals -r raw/bvecs -o sub-01
```

- **Reference volume.** The b-values are read, and the first volume with b ≤ 50 s/mm²
  (change with `-t`) is used as the registration reference and for the mask. The
  script stops if there is no such volume, or if the b-value or b-vector counts do
  not match the image. The index is saved to `diffusion/reference_volume.txt`.
- **Gradient rotation.** `eddy_correct` rotates each volume, so `fdt_rotate_bvecs`
  applies the same rotations to the b-vectors. `diffusion/bvecs` (rotated) is used by
  every later step.
- **One mask.** BET runs once, on the corrected reference b=0 (`-f 0.3`, change with
  `-f`). Alternatively, `-M` supplies an edited mask. The same file is used by dtifit,
  BEDPOSTX and probtrackx2. At the skull base, BET often removes the trigeminal nerve.
  Check this as described in
  [docs/roi_protocol.md §6](docs/roi_protocol.md#6-mask-coverage-critical-for-cn-v).

**Historical workflow.** `eddy_correct` is deprecated in current FSL and is kept because
it is what this project used. A replacement based on `eddy` would need the real
acquisition parameters: phase-encoding direction and total readout time for
`--acqp`, a volume `--index` file, and ideally `topup` with reversed phase-encoding b=0
images. It would then use `eddy`'s `*.eddy_rotated_bvecs` downstream. That workflow is not
included because those parameters are not available here and must not be guessed.

### 2. Tensor fit (branch A)

```bash
scripts/02_fit_tensor.sh sub-01
```

### 3. BEDPOSTX (branch B)

```bash
# Extra arguments go straight to bedpostx, e.g. the number of fibres per voxel
scripts/03_bedpostx.sh sub-01 -n 3
```

The output is always `sub-01/diffusion.bedpostX`, and that is the path
`04_tractography.sh` reads.

### 4. Tractography

ROIs are defined in [docs/roi_protocol.md](docs/roi_protocol.md). Run each side
separately:

```bash
scripts/04_tractography.sh -w sub-01 -l CNV_left \
  -x rois/CNV_left_seed.nii.gz \
  -W rois/CNV_left_meckel.nii.gz \
  -a rois/midline_and_mcp_left.nii.gz
```

By default the masks must be in **diffusion space** (on the `nodif` grid). The script
checks this and passes **no** `--xfm`/`--invxfm`. Transforms are needed only if the masks
were drawn in another space. Their creation and direction are described in
[docs/roi_protocol.md §5](docs/roi_protocol.md#5-bringing-masks-into-tracking-space).
The script also warns when ROI voxels fall outside the BEDPOSTX mask, because
probtrackx2 stops streamlines at the mask edge.

## Outputs

This repository produces the following. It does **not** extract tract-level FA/MD/AD/RD
statistics. That would need an extra, documented step: a tract-mask definition, a
threshold and a summary statistic. No such step is implemented here.

| Output | Meaning |
|--------|---------|
| `dti/dti_FA`, `dti_MD`, `dti_L1..L3`, `dti_V1..V3` | Voxel-wise tensor maps over the whole mask |
| `tract/<LABEL>/fdt_paths` | Number of probabilistic samples passing through each voxel (streamline count / density) |
| `tract/<LABEL>/waytotal` | Number of samples that met the waypoint/exclusion conditions |
| `tract/<LABEL>/fdt_paths_norm` | `fdt_paths / waytotal`, for display at a consistent threshold |
| `tract/<LABEL>/seeds_to_*` | Per-seed-voxel sample counts reaching each target (only with `-t`) |

`fdt_paths` is a sample-count map that depends on seed size, number of samples, and
tracking parameters. It is **not** a direct measure of anatomical connection
probability, axon count or nerve integrity.

### Example figure

**TODO (author):** if a shareable output exists, add `docs/figures/<name>.png` showing
the ROI placement and the reconstruction overlaid on the colour FA or b=0 image, with a
caption that gives:
- the image space (diffusion space of one subject, or another stated space)
- the display threshold (e.g. `fdt_paths_norm` > x)
- whether it is an **original research result** or an **illustration**.

No figure is included at present.

## Viewing results

```bash
fsleyes sub-01/dti/dti_FA \
  sub-01/tract/CNV_left/fdt_paths_norm -cm hot -dr 0.01 0.1
```

The display range above is only an example. Use the threshold recorded in
[docs/qc.md](docs/qc.md#7-tractography).

## Verification status

| Check | Status |
|-------|--------|
| `bash -n` on all scripts | Passed |
| ShellCheck 0.11.0 (`shellcheck -x scripts/*.sh`) | Passed, no warnings |
| Missing arguments, files, `FSLDIR` and FSL commands report a clear error | Checked manually |
| Full chain run with stub FSL commands (checks paths and arguments passed between scripts, b=0 selection when volume 0 is not b=0, bval/bvec count checks) | Passed |
| Run on real diffusion data with FSL | **Not done for this version of the scripts.** **TODO (author):** record it here if/when done, with FSL version and dataset |

To repeat the static checks:

```bash
for f in scripts/*.sh; do bash -n "$f"; done
shellcheck -x scripts/*.sh
```

## References

- FSL FDT user guide (dtifit, BEDPOSTX, probtrackx2): https://fsl.fmrib.ox.ac.uk/fsl/docs/#/diffusion/index
- Behrens TEJ et al. (2003). Characterization and propagation of uncertainty in
  diffusion-weighted MR imaging. *Magn Reson Med* 50:1077–1088.
- Behrens TEJ et al. (2007). Probabilistic diffusion tractography with multiple fibre
  orientations: what can we gain? *NeuroImage* 34:144–155.
- Smith SM (2002). Fast robust automated brain extraction. *Hum Brain Mapp* 17:143–155.
- ROI protocol reference: **TODO (author)**, see [docs/roi_protocol.md §8](docs/roi_protocol.md#8-reference-protocol).

## Licence

The code in this repository is released under the [MIT licence](LICENSE). FSL itself is
distributed under its own licence and is not included.
