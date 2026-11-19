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
| `diagnose_dem.m` | Checks how DeltaDTM stores land, sea and no-data |
| `data/slr/` | IPCC AR6 projections for the Lagos tide gauge (PSMSL 162) from the NASA Sea Level Projection Tool |
| `data/esia/esia_section1_claims.csv` | Claims extracted from the Section 1 assessment, with page numbers |
| `data/esia/esia_section2_claims.csv` | Claims extracted from the Section 2 assessment, with page numbers |

## Data (not stored in this repository)

- DeltaDTM v1.1, Pronk et al. (2024), *Scientific Data* 11, 273, https://doi.org/10.1038/s41597-024-03091-9 (CC BY 4.0). Place tiles and mask tiles in `data/dem/`.
- IPCC AR6 sea-level projections (Fox-Kemper et al. 2021; Garner et al. 2021, version 20210809), CC BY 4.0, via the NASA Sea Level Projection Tool.
- OpenStreetMap, (c) OpenStreetMap contributors (ODbL), downloaded by `get_osm_features.m`.
- Lagos-Calabar Coastal Highway Section 1 and Section 2 ESIA draft reports, Federal Ministry of Works (2024), public on the Federal Ministry of Environment website.

## Assumptions (so far)

- Elevations are metres above EGM2008, taken as mean sea level in 2020. The offset between EGM2008 and local mean sea level at Lagos is not yet applied.
- Sea level rise is counted from 2020 using the IPCC AR6 curve for Lagos (relative to 1995-2014).
- Lagos Lagoon and connected creeks count as sea (tidal, open to the ocean). Water reaches land only through connected cells (8-connectivity).
- Land sinking in M1 is uniform across the area. Uniform sinking is equivalent to an equal extra sea-level rise in a bathtub model. Spatially varying sinking comes later.
- Tides and storm surge are not included yet (method M3), so all years are for mean sea level and are late estimates.
- Road points over water (bridges) are left out.

## Licence

Code: MIT (see `LICENSE`). Data keep their own licences listed above.
