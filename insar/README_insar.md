# Measuring land sinking with Sentinel-1 radar (InSAR)

This folder records how `data/insar/lagos_vlm_s1_2017_2025.tif` was made. The map gives the
vertical land motion (mm per year) over the Lagos coast from January 2017 to December 2025. It
replaces the uniform, published sinking rates that the first version of M1 used.

## 1. Radar data and interferograms

- Sentinel-1A, path 1 ascending, IW mode, VV polarisation, 12-day repeat. Four bursts cover the
  highway: `001_000032_IW2`, `001_000033_IW2`, `001_000031_IW3`, `001_000032_IW3`.
- 255 Sentinel-1A dates with all four bursts, 2017-01-10 to 2025-12-30. Most of 2024 has no
  acquisitions on this path, so the time series has a gap there.
- Network: each date paired with its 3 next dates, 759 pairs. Processed by the ASF HyP3 service
  (job type `INSAR_ISCE_MULTI_BURST`, ISCE2 software, Copernicus GLO-30 DEM, 20 x 4 looks giving
  80 m pixels, phase filter strength 0.5, SNAPHU unwrapping, water mask on).
  748 pairs finished; 11 failed, all in early 2017. The list of pairs and bursts is in
  `hyp3_pairs.csv`.
- `fetch_and_clip.sh` downloads each product and keeps only the unwrapped phase, coherence,
  connected components and (once) the geometry files, clipped to 3.35-4.45 E, 6.33-6.62 N.

## 2. Time series (MintPy 1.6)

`LagosSenAT1.txt` is the MintPy settings file (`smallbaselineApp.py LagosSenAT1.txt`):

- Network inversion weighted by coherence (`var`), no pairs dropped.
- Troposphere: phase-height correlation removed per date (no weather model; an ERA5 correction
  needs a Copernicus key and is a possible later improvement).
- DEM error removed. No ramp removed: a test with a linear ramp per date made the east end of the
  map change by several mm/yr because the ramp is fitted mostly to the west, so it was not used.

## 3. Vertical rate and GPS tie (`make_vlm_product.py`)

1. The time series is re-referenced to the pixel that holds the two UNILAG GPS stations, ULAG and
   LAF1 (6.517 N, 3.398 E). The automatic MintPy reference was an urban pixel that is itself
   sinking about 13 mm/yr relative to UNILAG, so it was not used.
2. A straight line is fitted to each pixel's time series. The fit is repeated on 2019-2025 and
   2017-2023. Half of the spread of the three rates is added to the uncertainty.
3. Line-of-sight motion is divided by cos(incidence angle) (39-42 degrees here) to get vertical
   motion. This assumes no horizontal motion of the ground other than plate motion, which is the
   same for the whole scene and cancels out.
4. The GPS vertical rate at UNILAG is added so the map is tied to the Earth's centre (IGS20). Nevada
   Geodetic Laboratory daily series, median of one-year pair slopes (`gps_vertical_rate.m`):
   ULAG -2.8 mm/yr (2011.0-2013.8), LAF1 -0.6 mm/yr (2008.2-2012.7), mean -1.7 mm/yr. Both records
   end before the radar record starts, so the tie assumes the UNILAG rate did not change. The tie
   uncertainty is set to 2.5 mm/yr (the two stations differ by 2.2 mm/yr). Because it shifts every
   pixel together, it is sampled separately in the Monte Carlo.
5. Land pixels with temporal coherence of at least 0.5 are kept (64,175 pixels of 80 m).

Bands of the GeoTIFF (WGS84 lat/lon, about 80 m): 1 vertical rate (mm/yr, positive = up),
2 local 1-sigma uncertainty (mm/yr), 3 temporal coherence.

## 4. What the map shows

Percentiles of all kept pixels (mm/yr, negative = sinking): 10th -12.0, median -0.8, 90th +3.0.
A study of Lagos with Sentinel-1 data from 2015 to 2025, also tied to GPS, reports a 10th to 90th
percentile range of -11.4 to +0.76 mm/yr (summarised on PreventionWeb,
https://www.preventionweb.net/quick/104143; authors and journal still to be confirmed before
citing). The low end agrees within 1 mm/yr; our upper end is about 2 mm/yr higher, which is within
our GPS tie uncertainty.

- Fastest sinking (15-30 mm/yr) is on the edges of reclaimed land along the lagoon and on recent
  sand fill.
- The older urban area of Victoria Island and Lekki Phase 1 shows close to zero motion at 80 m
  pixels. These pixels are dominated by buildings, many on deep foundations. Roads and open ground
  on fill can sink faster than the buildings around them, so the rate under the highway could be
  faster than the map shows in built-up areas. Ikuemonisan (2025, Discover Environment 3:148)
  gives at least 34 mm/yr for Lekki and Victoria Island, which this map does not show. The reason
  for the difference is not yet known (the 80 m pixels above are one possible cause), so the
  uniform rates 11.4 and 34 mm/yr are kept as sensitivity cases in `run_m3_extremes`.
- East of about 4.15 E (towards Akodo and the Ogun border) the coast sinks 10-17 mm/yr relative
  to UNILAG. This result holds in all three time windows (2017-2025, 2019-2025, 2017-2023), but
  the pixels there have lower coherence (0.5-0.7) and are 80-110 km from the GPS tie, so it is the
  least certain part of the map.

## Credits

- Contains modified Copernicus Sentinel data 2017-2025, processed by ESA.
- ASF HyP3: Hogenson, K. et al. (2020), Hybrid Pluggable Processing Pipeline (HyP3): a cloud-native
  infrastructure for generic processing of SAR data, Zenodo, https://doi.org/10.5281/zenodo.4646138.
- ISCE2: InSAR Scientific Computing Environment, https://github.com/isce-framework/isce2.
- MintPy: Yunjun, Z., Fattahi, H., Amelung, F. (2019), Small baseline InSAR time series analysis:
  unwrapping error correction and noise reduction, Computers & Geosciences 133, 104331.
- GPS: Blewitt, G., Hammond, W. C., Kreemer, C. (2018), Harnessing the GPS data explosion for
  interdisciplinary science, Eos 99.
- Ikuemonisan, F. E., Ozebo, V. C., Olatinsu, O. B. (2021), Investigation of Sentinel-1-derived land
  subsidence using wavelet tools and triple exponential smoothing algorithm in Lagos, Nigeria,
  Environmental Earth Sciences 80, 722.
