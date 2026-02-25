#!/usr/bin/env python3
"""Load a plotfile with yt and inspect qc by AMR level to see the level-1 error."""
import sys
import os
import numpy as np
import yt

def main():
    if len(sys.argv) < 2:
        plt_dir = "/home/ghosh/Runs/remote/ERF/2D_wAMR_rising_bubble/.run_BF02_moist_bubble_AMR2.matrix.nproc00004/plt00300"
    else:
        plt_dir = sys.argv[1]
    if not os.path.isdir(plt_dir):
        print("Not a directory:", plt_dir)
        sys.exit(1)

    ds = yt.load(plt_dir)
    print("Dataset:", ds)
    print("Current time:", ds.current_time)
    print("Max level:", ds.max_level)
    print("Field list (first 30):", [f for f in ds.field_list][:30])

    # Find qc field name (might be ('stream', 'qc') or similar)
    qc_fields = [f for f in ds.field_list if len(f) >= 2 and f[1] == 'qc']
    if not qc_fields:
        qc_fields = [f for f in ds.derived_field_list if len(f) >= 2 and f[1] == 'qc']
    print("qc-related fields:", qc_fields)

    # Per-level: iterate over grids (yt AMReX stores level in grid.Level or grid.level)
    for lev in range(ds.max_level + 1):
        lev_grids = [g for g in ds.index.grids if getattr(g, 'Level', getattr(g, 'level', -1)) == lev]
        if not lev_grids:
            print(f"Level {lev}: no grids")
            continue
        qc_vals = []
        for g in lev_grids:
            try:
                qc_vals.append(g[('boxlib', 'qc')].flatten())
            except Exception as e:
                print(f"Level {lev} grid:", e)
                continue
        qc = np.concatenate(qc_vals) if qc_vals else np.array([])
        qc = np.atleast_1d(qc)
        qc = qc[np.isfinite(qc)]
        nz = (qc > 1e-12).sum()
        print(f"Level {lev}: ngrids={len(lev_grids)} ndata={len(qc)} qc min={qc.min():.6e} max={qc.max():.6e} mean={qc.mean():.6e} sum={qc.sum():.6e} n_nonzero={nz}")

    # Per-level grids: get qc from each grid at each level
    print("\nPer-level grid qc summary:")
    for lev in range(ds.max_level + 1):
        grids_lev = [g for g in ds.index.grids if getattr(g, 'Level', getattr(g, 'level', -1)) == lev]
        print(f"  Level {lev}: {len(grids_lev)} grids")
        for i, g in enumerate(grids_lev):
            try:
                arr = g[('boxlib', 'qc')]
                qc = arr.flatten()
                qc = qc[np.isfinite(qc)]
                print(f"    grid {i}: shape={arr.shape} qc min={qc.min():.6e} max={qc.max():.6e} sum={qc.sum():.6e}")
            except Exception as e:
                print(f"    grid {i}: {e}")

    # Level 1: which cells are zero vs non-zero (spatial)
    print("\nLevel 1 zero pattern (per grid):")
    for lev in [1]:
        grids_lev = [g for g in ds.index.grids if getattr(g, 'Level', getattr(g, 'level', -1)) == lev]
        for i, g in enumerate(grids_lev):
            arr = g[('boxlib', 'qc')]
            nz = (arr > 1e-12).sum()
            nzero = (arr <= 1e-12).sum()
            print(f"  L1 grid {i}: shape={arr.shape} zero_cells={nzero} nonzero_cells={nz} (zero_frac={nzero/arr.size:.3f})")

if __name__ == "__main__":
    main()
