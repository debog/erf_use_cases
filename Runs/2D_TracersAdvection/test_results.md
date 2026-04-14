# Tracer Particle AMR Test Results (2026-04-08)

Branch: `dg/particles_w_AMR`

All cases use anisotropic refinement (2,1,2) per level and run for
400 coarse steps. "PASS" means 400 steps completed and the solution
matches the AMR0 reference.

## Flat Terrain

| Case                | 1-Way | Reason              | 2-Way | Reason              |
|---------------------|-------|---------------------|-------|---------------------|
| over_flat (AMR0)    | PASS  |                     | PASS  |                     |
| AMR1_box_fullz      | PASS  |                     | PASS  |                     |
| AMR1_box_partialz   | PASS  |                     | PASS  |                     |
| AMR1_particlecount  | PASS  |                     | PASS  |                     |
| AMR2_box_fullz      | PASS  |                     | FAIL  | FPE at step 237     |
|                     |       |                     |       | during L2 time      |
|                     |       |                     |       | integration         |
| AMR2_box_partialz   | PASS  |                     | FAIL  | Negative density    |
|                     |       |                     |       | at step 332 on L2   |
| AMR2_particlecount  | PASS  |                     | PASS  |                     |

## Terrain (Witch of Agnesi)

| Case                | 1-Way | Reason              | 2-Way | Reason              |
|---------------------|-------|---------------------|-------|---------------------|
| over_hill (AMR0)    | PASS  |                     | PASS  |                     |
| AMR1_box_fullz      | FAIL  | Negative density    | PASS  |                     |
|                     |       | at step 373 on L1   |       |                     |
| AMR1_box_partialz   | FAIL  | FPE at step 305     | FAIL  | Heap corruption     |
|                     |       | during L1 time      |       | at step 100         |
|                     |       | integration         |       |                     |
| AMR1_particlecount  | FAIL  | Heap corruption     | FAIL  | Segfault at step 61 |
|                     |       | at step 100         |       | during regrid       |
| AMR2_box_fullz      | FAIL  | FPE at step 87      | FAIL  | FPE at step 85      |
|                     |       | during L2 time      |       | during L2 time      |
|                     |       | integration         |       | integration         |
| AMR2_box_partialz   | FAIL  | FPE at step 73      | FAIL  | FPE at step 36      |
|                     |       | during L2 time      |       | during L2 time      |
|                     |       | integration         |       | integration         |
| AMR2_particlecount  | FAIL  | Heap corruption     | FAIL  | Heap corruption     |
|                     |       | at step 100         |       | at step 101         |
|                     |       | during regrid       |       | during regrid       |

## Notes

All flat-terrain cases pass with one-way coupling, including the
AMR2 box cases that fail with two-way coupling. All terrain AMR
cases fail with both coupling types (except AMR1_box_fullz which
passes with two-way only).

Failure modes:

- **FPE in advance_dycore**: Spurious oscillations at coarse-fine
  boundaries grow until NaN/Inf reaches `powf64` in the RHS
  computation (`ERF_TI_utils.H:41` via `ERF_TI_slow_rhs_pre.H:26`).

- **Negative density**: Same instability but caught earlier by
  `check_for_negative_theta` (`ERF.cpp:3237`).

- **Heap corruption**: Flow state corrupted by bad coarse-fine
  interpolation; crash manifests during memory operations (regrid,
  plotfile write, or particle redistribute).

Root cause for terrain cases: AMReX index-space interpolation
kernels (`mf_cell_cons_lin_interp`, `interp_face_reg`) assume
uniform z-spacing, which does not hold with terrain-following
coordinates. The two-way AMR1_box_fullz case survives because
averaging-down partially stabilizes the solution; one-way lacks
this feedback.
