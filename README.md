# Beyond the Bathtub: Coastal Risk for the Lagos Coastal Infrastructure Corridor

MATLAB and Simulink project for the MathWorks Global Student Challenge 2026
(Sustainability and Renewable Energy: *Coastline Prediction using Existing Climate Change Models*).

**Status:** analysis complete (methods M0 to M3, uncertainty runs and app). Video in preparation.

## Key findings

1. The highway assessment's bathtub screening (M0) finds no road km reached by the sea before 2100 under the IPCC AR6 median (SSP2-4.5). The same elevation data, with each missing process added one at a time, gives a very different answer: 57 of 109 road km reached by the ordinary high tide by 2100, and 67 km by a 10-year storm.
2. Land sinking is the single largest driver. Adding 11.4 mm/yr of sinking (M1) moves the first road km from 2112 to 2056. In 2000 Monte Carlo runs the sinking rate ranks above the sea-level percentile and the Bruun factor.
3. About 3 km of the route (near km 50 to 54, Orimedu) crosses tidal wetland that is below today's high tide. These low channels are visible on satellite imagery.
4. Shoreline erosion alone reaches only about 3 road km by 2100. Where it does matter (CH 3+800), the model reproduces the assessment's own forecast. At CH 33+600 to 37+500 the assessment's forecast does not follow from its own measured rate.
5. Measured sinking (InSAR or GPS) along the corridor is the most valuable next measurement before the road levels are fixed.

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

## Results

All results below use the IPCC AR6 projection for the Lagos tide gauge (PSMSL 162), the 109 road km mapped in OpenStreetMap, and the 10% rule (a km is reached when at least 100 m of it is under water or behind the shoreline).

### Method ladder (SSP2-4.5 median, land sinking 11.4 mm/yr, Bruun factor 50)

| Method | Today (2020) | By 2030 | By 2050 | By 2100 | First year |
| --- | ---: | ---: | ---: | ---: | ---: |
| M0 bathtub (assessment approach) | 0 | 0 | 0 | 0 | 2112 |
| M1 + land sinking | 0 | 0 | 0 | 22 | 2056 |
| M2 + moving beach | 0 | 1 | 2 | 25 | 2030 |
| M3 + ordinary high tide | 3 | 11 | 15 | 57 | 2020 |
| M3 + 10-year storm | 13 | 14 | 26 | 67 | 2020 |

Values are road km reached (out of 109). Each row includes everything in the rows above it. M0 uses no sinking.

### Erosion alone (Simulink shoreline model)

The assessments give measured shoreline change rates (end point rates, 1984 or 1986 to 2024) for 103 of the 109 road km. Run forward in the Simulink model `shoreline_model.slx`:

| Scenario | Bruun factor (m per m) | Road km reached by 2050 | By 2100 | Median retreat by 2100 (m) |
| --- | ---: | ---: | ---: | ---: |
| SSP2-4.5 | 0 | 2 | 3 | 34 |
| SSP2-4.5 | 50 | 2 | 3 | 48 |
| SSP2-4.5 | 100 | 2 | 3 | 61 |
| SSP5-8.5 | 0 | 2 | 3 | 34 |
| SSP5-8.5 | 50 | 2 | 3 | 58 |
| SSP5-8.5 | 100 | 2 | 3 | 81 |

Erosion on its own reaches only the few km where the beach is already close to the route.

### Uncertainty (2000 Monte Carlo runs per scenario)

Each run draws a sea-level percentile (5th to 95th), a sinking rate (0 to 34 mm/yr) and a Bruun factor (0 to 100), and combines the high tide, the lagoon level and erosion.

| Scenario | Road km reached by 2050, median (5 to 95%) | By 2100, median (5 to 95%) | Main driver |
| --- | --- | --- | --- |
| SSP2-4.5 | 21 (14 to 36) | 67 (22 to 93) | sinking rate, then sea-level percentile, then Bruun factor |
| SSP5-8.5 | 21 (14 to 40) | 68 (26 to 103) | same order |

Even the 5th percentile result for 2100 (22 km) is far above the bathtub answer (0 km).

The closed-form erosion formula used in these runs was checked against the Simulink model; the largest difference over 130 years was 0.000 m.

### Checks against the highway assessments

| Assessment statement | Page | What this project finds |
| --- | --- | --- |
| A 0.5 m rise "will not affect" the road (Climate Central screening tool) | S1 p. 4-77, S2 p. 4-95 | True for a bathtub with no sinking (M0 reaches no road km until 2112). Not true once sinking, tide and storms are added (table above). Only one water level (0.5 m) is tested and no road or embankment height is given. |
| Erosion reaches the road within 10 to 20 years (2034 to 2044) at CH 3+800 | S1 p. 4-62 | Agrees. Road about 62 m from the shore, measured rate -6.5 m/yr, reached in 2030. |
| Same forecast at CH 33+600 to 37+500 | S1 p. 4-62 | Does not follow from the assessment's own rate. The road is 177 to 234 m from the shore and the stated rate is 0 to -0.5 m/yr, so the trend alone would take more than 350 years. |
| Section 2 flood risk table (1022.34 / 4981.07 / 3873.15 ha) | S2 p. 4-96 | Same numbers and place names as Section 1 Table 4.20 (p. 4-79). The places listed lie west of Eleko, in Section 1. The total row prints 976.56 ha; the classes sum to 9876.56 ha. |
| Sea-level rise text and values | S2 p. 4-93 | Same text and values as Section 1 p. 4-76. |
| Land subsidence | S2 p. 4-28 | Mentioned as a construction risk only. No rate is given or used. |

Full claim lists with page numbers: `data/esia/esia_section1_claims.csv` and `data/esia/esia_section2_claims.csv`.

### Figures

Route and 1 km segments used in the analysis:

![Highway segments](docs/figures/highway_segments.png)

The lowest stretch of the route (km 50 to 54), with the low tidal channels:

![Low stretch check](docs/figures/low_stretch_check.png)

The interactive app `CoastalRiskExplorer` (red: road km reached by the chosen year):

![Sea Reach Explorer app](docs/figures/app_screenshot.png)

## How to run

MATLAB R2026b with Mapping, Image Processing, Statistics and Machine Learning Toolboxes, and Simulink.

1. `setup_project` creates the folders and checks the toolboxes.
2. Place the DeltaDTM tiles N06E003 and N06E004 (with their mask tiles) in `data/dem/`.
3. `get_osm_features` then `make_segments` download the route and cut it into 1 km segments.
4. `run_m0_bathtub` runs the bathtub method at fixed water levels.
5. `run_m1_sinking` builds the flood level map and runs M0 and M1 by year.
6. `run_m3_extremes` adds the high tide and storm levels (uses `data/gtsm/gtsm_lagos_stations.csv`; `extract_gtsm` rebuilds it from the Copernicus files if needed).
7. `get_place_coords` then `run_m2_shoreline` build and run the Simulink shoreline model and print the full method ladder.
8. `run_uncertainty` runs the Monte Carlo.
9. `CoastalRiskExplorer` opens the app.

Results are written to `results/` and figures to `results/figures/`.

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
| `run_uncertainty.m` | Step 5: Monte Carlo (2000 runs) over sea-level quantile, sinking rate and Bruun factor; chance each road km is reached by 2050 and 2100; checks the closed-form shoreline solution against Simulink |
| `CoastalRiskExplorer.m` | Interactive app: pick method, scenario, percentile, sinking, Bruun factor and year; map and chart of road km reached |
| `get_place_coords.m` | Locates the Section 2 beach communities (OpenStreetMap, with the assessment's sampling points as fallback) |
| `build_shoreline_model.m` | Builds the Simulink shoreline model `shoreline_model.slx` (dy/dt = r - B s(t) + D L y) |
| `run_m2_shoreline.m` | Step 4: moving beach (M2) with the Simulink model, check against the assessment's erosion forecast, full method ladder |
| `data/esia/shoreline_rates_section1.csv`, `..._section2.csv` | Measured shoreline change rates from the assessments, with page numbers |
| `diagnose_low_stretch.m` | Checks the lowest stretch of the route (ground heights, low channels) |
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

## Assumptions and limits

- Elevations are metres above EGM2008, taken as mean sea level in 2020. The offset between EGM2008 and local mean sea level at Lagos is not yet applied.
- Sea level rise is counted from 2020 using the IPCC AR6 curve for Lagos (relative to 1995-2014).
- Lagos Lagoon and connected creeks count as sea (tidal, open to the ocean). Water reaches land only through connected cells (8-connectivity).
- Land sinking in M1 is uniform across the area. Uniform sinking is equivalent to an equal extra sea-level rise in a bathtub model. Spatially varying sinking is not modelled.
- M3 adds tide and storm levels from GTSM (1985-2014) as fixed heights above each year's mean sea level; changes in storminess are not included. The 95% upper bounds of these return levels at Lagos are unrealistically large (tens of metres) from the bootstrap fit, so only the best fit is used.
- Tide and storm peaks enter from the open sea only. Lagoon water follows the mean sea level but not the ocean tide or surge (lower bound); the run also prints the upper bound where the lagoon gets the full ocean peak.
- A bathtub fills every connected low cell to the event peak. Real storm peaks last hours, so flooding inland of the shore is overstated for short events; results for the road are the year the water can first reach it, not a prediction of damage.
- M2 uses the assessments' own measured shoreline change rates (1984-2024). Accretion is set to zero, because past gains came mostly from port and reclamation sand fill. Sea-level rise above the historical rate (3.25 mm/yr, global mean 1993-2018, IPCC AR6) adds retreat through the Bruun rule with factors 0, 50 and 100 m per m. The Bruun rule is a rough estimate and is often criticised (Cooper and Pilkey 2004), so it is shown as a range. Alongshore smoothing is off (D = 0) because no calibrated value exists here.
- Uncertainty runs sample the AR6 5th to 95th percentile range only (tails beyond are not sampled), sinking uniformly between 0 and 34 mm/yr, and the Bruun factor between 0 and 100. Elevation model error is not sampled.
- Our chainage starts at the westernmost mapped point of the road and lines up with the assessment chainage to within about 1 km.
- Road points over water (bridges) are left out. A 1 km segment counts as reached when at least 10% of its length (100 m) is under water, so a single low pixel does not decide a whole kilometre.
- Near km 50-54 (about 3.88-3.92 E) the elevation model shows two low channels (below 0.6 m) from the beach to the route. A channel from the beach inland is visible there on satellite imagery (checked on Google Maps, November 2026), so the low ground is real: the route crosses tidal wetland that is below today's high tide over a few hundred metres. A finished road would be raised or bridged here; the result means the design height at these crossings must account for the water levels below, which the assessment does not state.

## How generative AI was used

This project used generative AI as a working assistant, and every number in it comes from the data sources listed above, run in MATLAB and Simulink.

- **Claude (Anthropic)** was used to scope the question, read the two highway assessments and list their claims with page numbers (so any reader can check each one in the PDF), draft the MATLAB scripts and the Simulink model builder, and debug errors from MATLAB runs. All code was run and checked in MATLAB Online by the author. Where the AI suggested a cause for a strange result (for example, the low stretch near Orimedu), the author checked it against satellite imagery before keeping it.
- **What AI did not do:** it did not supply any data values. Sea-level, elevation, tide and shoreline numbers come only from the cited files and reports.

## Licence

Code: MIT (see `LICENSE`). Data keep their own licences listed above.
