# Beyond the Bathtub: Coastal Risk for the Lagos Coastal Infrastructure Corridor

MATLAB and Simulink project for the MathWorks Global Student Challenge 2026
(Sustainability and Renewable Energy: *Coastline Prediction using Existing Climate Change Models*).

**Status:** work in progress.

## Question

The environmental impact assessments for Sections 1 and 2 of the Lagos-Calabar Coastal Highway
(Federal Ministry of Works, 2024; km 0 to 47.5 and km 47.5 to 104) both state that a 0.5 m water
level rise "will not affect" the road (Section 1 p. 4-77, Section 2 p. 4-95), using a bathtub-style
screening tool. This project compares four methods
on the same corridor, each adding one process:

| Method | Includes |
| --- | --- |
| M0 Bathtub | Sea-level rise on the elevation model, connected to the sea |
| M1 Sinking land | M0 plus vertical land motion |
| M2 Moving beach | M1 plus shoreline retreat from a calibrated shoreline model |
| M3 Extreme water | M2 plus tide and storm surge return levels |

For each 1 km segment of the road, the project reports the first year of impact under each
method and the gap between them. OpenStreetMap does not yet map the whole road, so results are
also reported for a coastal corridor (land within 2 km of the ocean, in 1 km alongshore strips)
that covers the full 104 km.

## Repository layout

| Path | Contents |
| --- | --- |
| `project_config.m` | Study area, folders and settings |
| `setup_project.m` | Creates folders and checks toolboxes |
| `get_osm_features.m` | Highway, refinery and port outlines from OpenStreetMap |
| `make_segments.m` | Merges the highway pieces into one centreline and cuts it into 1 km segments |
| `load_dem.m` | Reads and joins DeltaDTM tiles and masks |
| `bathtub_flood.m` | Method M0 (connected bathtub) |
| `cell_area_km2.m` | Grid cell areas |
| `run_m0_bathtub.m` | First M0 run at fixed sea-level values, with results per road segment and per corridor strip |
| `flood_level_map.m` | Lowest water level at which each cell floods, so any sea-level curve converts to years |
| `run_m1_sinking.m` | Step 2: IPCC AR6 sea level by year (M0) and with land sinking (M1); first wet year per road km and coastal strip |
| `run_m3_extremes.m` | Step 3: adds high tide and 1, 10 and 100-year storm water levels (M3); method ladder figure |
| `extract_gtsm.m` | Rebuilds the coastal extreme water level table from the Copernicus NetCDF files |
| `data/gtsm/gtsm_lagos_stations.csv` | High tide and return water levels at 8 coastal points along Lagos (GTSM, ERA5, 1985-2014) |
| `diagnose_dem.m` | Checks how DeltaDTM stores land, sea and no-data |
| `data/slr/` | IPCC AR6 projections for the Lagos tide gauge (PSMSL 162) from the NASA Sea Level Projection Tool |
| `data/esia/esia_section1_claims.csv` | Claims extracted from the Section 1 assessment, with page numbers |
| `data/esia/esia_section2_claims.csv` | Claims extracted from the Section 2 assessment, with page numbers |

## Data (not stored in this repository)

- DeltaDTM v1.1, Pronk et al. (2024), *Scientific Data* 11, 273, https://doi.org/10.1038/s41597-024-03091-9 (CC BY 4.0). Place tiles and mask tiles in `data/dem/`.
- IPCC AR6 sea-level projections (Fox-Kemper et al. 2021; Garner et al. 2021, version 20210809), CC BY 4.0, via the NASA Sea Level Projection Tool.
- Copernicus Climate Change Service, Global sea level change indicators from 1950 to 2050 derived from reanalysis and high resolution CMIP6 climate projections, DOI 10.24381/cds.6edf04e0 (CC BY), GTSM v3 by Deltares.
- OpenStreetMap, (c) OpenStreetMap contributors (ODbL), downloaded by `get_osm_features.m`.
- Lagos-Calabar Coastal Highway Section 1 and Section 2 ESIA draft reports, Federal Ministry of Works (2024), public on the Federal Ministry of Environment website.

## Assumptions (so far)

- Elevations are metres above EGM2008, taken as mean sea level in 2020. The offset between EGM2008 and local mean sea level at Lagos is not yet applied.
- Sea level rise is counted from 2020 using the IPCC AR6 curve for Lagos (relative to 1995-2014).
- Lagos Lagoon and connected creeks count as sea (tidal, open to the ocean). Water reaches land only through connected cells (8-connectivity).
- Land sinking in M1 is uniform across the area. Uniform sinking is equivalent to an equal extra sea-level rise in a bathtub model. Spatially varying sinking comes later.
- M3 adds tide and storm levels from GTSM (1985-2014) as fixed heights above each year's mean sea level; changes in storminess are not included. The 95% upper bounds of these return levels at Lagos are unrealistically large (tens of metres) from the bootstrap fit, so only the best fit is used.
- Tide and storm peaks enter from the open sea only. Lagoon water follows the mean sea level but not the ocean tide or surge (lower bound); the run also prints the upper bound where the lagoon gets the full ocean peak.
- A bathtub fills every connected low cell to the event peak. Real storm peaks last hours, so flooding inland of the shore is overstated for short events; results for the road are the year the water can first reach it, not a prediction of damage.
- Road points over water (bridges) are left out. A 1 km segment counts as reached when at least 10% of its length (100 m) is under water, so a single low pixel does not decide a whole kilometre.
- Near km 50-54 (about 3.88-3.92 E) the elevation model shows two low channels (below 0.6 m) from the beach to the route. A channel from the beach inland is visible there on satellite imagery (checked on Google Maps, November 2026), so the low ground is real: the route crosses tidal wetland that is below today's high tide over a few hundred metres. A finished road would be raised or bridged here; the result means the design height at these crossings must account for the water levels below, which the assessment does not state.

## Licence

Code: MIT (see `LICENSE`). Data keep their own licences listed above.
