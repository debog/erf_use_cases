# GATE Test Case Configurations

This directory contains override configurations for different GATE test cases.

## Available Cases

### sdm_amsu
Standard GATE case with uniform vertical grid spacing.

**Key Features:**
- Domain: 12.8 km × 12.8 km × 4 km
- Resolution: 128 × 128 × 100 cells (uniform vertical spacing)
- Duration: 24 hours (86400 seconds)
- Time step: 0.3 seconds with MRI ratio 4
- Buoyancy type: 1
- SDM diagnostics: Every 100 steps
- Aerosol distribution: Uses std_radius parameter
- Output: Every 2000 steps (checkpoints and plots)

### sdm_amsu_z_nonuniform
GATE case with non-uniform vertical grid stretching for better resolution near surface.

**Key Features:**
- Domain: 100 km × 100 km × 21 km
- Resolution: 200 × 200 × 230 cells (non-uniform vertical spacing)
- Duration: 36 hours (129600 seconds)
- Time step: 3.0 seconds with fast dt 0.6 seconds
- Non-uniform vertical levels (230 levels): Fine near surface (50m), stretched above
- Rayleigh damping enabled (above 2000m)
- Buoyancy type: 2
- SDM diagnostics: Disabled (-1)
- Aerosol distribution: Uses geomstd_radius parameter
- Output: Every 100 steps for plots, 20000 for checkpoints
- Additional output variables: qsnow, qgraup, qi

## Parameter Inheritance

All cases inherit common parameters from `base.inputs`:
- Problem name, periodicity, boundary conditions
- MOST parameters (ustar, tstar, qstar, z0)
- LES model (Smagorinsky with Cs=0.17)
- Custom forcing settings
- Perturbation parameters

Override files specify case-specific parameters that differ between simulations.
