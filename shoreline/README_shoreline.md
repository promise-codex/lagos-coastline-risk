# Our own shorelines from Landsat and Sentinel-2

This folder holds the scripts that made the water-index composites in
`data/shoreline/`. The shoreline positions and rates are then measured in
MATLAB by `extract_shorelines.m`.

## Data

- Landsat 5, 7, 8 and 9 Collection 2 Level-2 surface reflectance (USGS),
  green and SWIR-1 bands, 30 m.
- Sentinel-2 Level-2A (ESA Copernicus), bands B03 (10 m) and B11 (20 m).
- Both read from the Microsoft Planetary Computer STAC catalogue with
  odc-stac. Scenes with more than 80% cloud are skipped.
- Area: 3.35 to 4.42 E, 6.36 to 6.47 N, in UTM zone 31N (EPSG:32631).

## Steps

1. Per scene, mask bad pixels.
   - Landsat: QA_PIXEL bits 0 (fill), 1 (dilated cloud), 3 (cloud),
     4 (cloud shadow); DN outside 7273 to 43636. Reflectance =
     DN x 2.75e-5 - 0.2.
   - Sentinel-2: SCL classes 0, 1, 3, 8, 9, 10, 11 (no data, saturated,
     cloud shadow, cloud, cirrus, snow). Reflectance = (DN + offset) / 10000,
     with offset -1000 for processing baseline 04.00 and later.
2. MNDWI = (green - SWIR1) / (green + SWIR1) (Xu 2006).
3. Median MNDWI of all clear looks in each epoch, and the number of clear
   looks per pixel. The median of many images taken at random tide stages
   sits near the mid-tide line (the idea of Digital Earth Australia
   Coastlines, Bishop-Taylor et al. 2021). No tide filter is applied.
4. Epochs:
   - Landsat 1984-1987 pooled, labelled 1986 (mean image date).
   - Landsat 1988-1997: the archive has almost no images of this coast
     (1991: one scene, no clear looks), so this period has no shoreline.
   - Landsat 1998-2012 in 3-year epochs, each labelled with its mean image
     date. Single years here have a median of only 1 to 3 clear looks,
     because of cloud and the Landsat 7 scan-line gaps after May 2003, which
     is too few for a stable median.
   - Landsat yearly 2013-2025 (Landsat 8 and 9, 4 to 25 clear looks).
   - Sentinel-2 yearly 2016-2025, averaged to 20 m (the size of its SWIR band).
5. `clip_to_coast.py` keeps only a strip from 3 km inland to 1.5 km out to
   sea from the 2020 Landsat ocean edge, to keep the files small. Every road
   transect fits inside this strip.

Single-year Landsat composites for 1998-2012 were also made and checked;
they are not stored because the 3-year epochs replace them.

## For the U-Net (step 7)

- `make_s2_band_composites.py`: yearly median Sentinel-2 reflectance of six
  bands (B02, B03, B04, B08, B11, B12) at 20 m, same scenes and cloud mask
  as above, coastal strip only.
- `make_worldcover_labels.py`: ESA WorldCover 2020 and 2021 water class
  (80) on the same 20 m grid (water if at least half of the 10 m cells are
  water). WorldCover is made by ESA with its own classifier, so it is
  independent of our water index, but it has its own errors.

## Commands

```
python make_mndwi_composites.py <out> landsat_early
python make_mndwi_composites.py <out> landsat
python make_mndwi_composites.py <out> landsat_pooled
python make_mndwi_composites.py <out> sentinel2
python clip_to_coast.py <out> ../data/shoreline
python make_s2_band_composites.py ../data/shoreline ../data/shoreline/sentinel2_mndwi_2021.tif
python make_worldcover_labels.py ../data/shoreline/sentinel2_bands_2021.tif ../data/shoreline
```

Python 3.12 with numpy, rasterio, scipy, xarray, dask, odc-stac,
pystac-client and planetary-computer.

## Output format

GeoTIFF, UTM 31N, band 1 = median MNDWI x 10000 (int16, -32768 = no data),
band 2 = number of clear looks.

## Known limits

- No tide correction. The tidal range at Lagos is about 1 m and the beach is
  fairly steep, so the waterline moves by roughly 10 to 30 m with the tide
  (our estimate for beach slopes of 1:10 to 1:30, not measured); the
  median over many looks reduces this but does not remove it.
- In the early epochs few looks are available, so those positions are less
  certain. The rate is a linear regression over all epochs, so one noisy
  epoch has limited weight.
- Land made by people (reclamation, port works) shows as fast seaward
  advance. `extract_shorelines.m` flags km faster than +10 m/yr.
