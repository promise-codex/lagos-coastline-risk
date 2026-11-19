function cfg = project_config()
%PROJECT_CONFIG Settings shared by every script in the Lagos coastline project.
%   cfg = project_config() returns a struct with the study area, folder
%   paths and the sea-level values used by the bathtub method (M0).

% Project root = the folder that holds this file
cfg.root = fileparts(mfilename('fullpath'));

% Folders (created by setup_project.m)
cfg.dataDir    = fullfile(cfg.root, 'data');
cfg.demDir     = fullfile(cfg.dataDir, 'dem');      % DeltaDTM tiles go here
cfg.osmDir     = fullfile(cfg.dataDir, 'osm');      % OpenStreetMap downloads
cfg.resultsDir = fullfile(cfg.root, 'results');
cfg.figDir     = fullfile(cfg.resultsDir, 'figures');

% Study area: the Lagos part of the coastal highway, Section 1 (km 0 to
% 47.5, Victoria Island to Eleko) and Section 2 (km 47.5 to 104, Eleko to
% Ode-Omi at about 4.37 E near the Ogun State border), in degrees WGS84.
cfg.latlim = [6.35 6.65];
cfg.lonlim = [3.35 4.40];

% Coastal corridor: land within this distance of the ocean, cut into
% alongshore strips. Used where the road itself is not yet mapped.
cfg.corridor_km = 2;     % width inland from the ocean edge
cfg.strip_km    = 1;     % alongshore length of each strip

% Sea-level rise values for the first bathtub test (metres above the
% present mean sea level). 0.5 m is the value used in the highway
% assessment's Fig. 4.58. The AR6 values per scenario and year replace
% these in the next step.
cfg.slr_m = [0.5 1.0 1.5 2.0];

% Which DeltaDTM water classes act as the "sea" that floods inland.
% DeltaDTM mask values: 0 land, 1 ocean, 2 lakes, 3 rivers.
% Lagos Lagoon is tidal and open to the ocean, so lakes and rivers are
% included by default. Set to 1 to use the ocean only.
cfg.waterSeedClasses = [1 2 3];

% ---- Step 2 (M1): sea level by year plus sinking land -----------------
% IPCC AR6 projections for the Lagos tide gauge (PSMSL 162), downloaded
% from the NASA Sea Level Projection Tool. Values are relative to the
% 1995-2014 average. We count rise from cfg.refYear and treat the
% elevation model's zero (EGM2008) as mean sea level in that year.
% DeltaDTM corrects Copernicus DEM (radar, 2011-2015) with ICESat-2 and
% GEDI laser data (2018 onwards), so 2020 is an approximation; both this
% and the EGM2008-to-sea-level offset are listed in the README assumptions.
cfg.slrFile  = fullfile(cfg.dataDir, 'slr', 'ipcc_ar6_sea_level_projection_psmsl_id_162.xlsx');
cfg.refYear  = 2020;
cfg.years    = 2020:2150;
% Scenarios used: {confidence, scenario, quantile}
cfg.slrCases = {'medium', 'ssp126', 50; ...
                'medium', 'ssp245', 50; ...
                'medium', 'ssp585', 50; ...
                'low',    'ssp585', 83};
% Uniform land sinking rates tested (mm per year, positive = sinking).
%   0     IPCC AR6 assumption (its land-motion term for Lagos is about 0)
%   5     round low value for comparison
%   11.4  highest rate in a 2015-2025 Sentinel-1 study summarised on
%         PreventionWeb (authors still to be confirmed before citing)
%   34    lower bound given for Lekki and Victoria Island by
%         Ikuemonisan (2025), Discover Environment 3:148
cfg.subsidence_mm_yr = [0 5 11.4 34];
% Measured land motion (step 2b). Vertical rate map from our own
% Sentinel-1 radar processing, 2017-2025, tied to the UNILAG GPS stations
% (see insar/README_insar.md). The uniform rates above are kept as a
% sensitivity test; the method ladder and the Monte Carlo use this map.
cfg.insarFile       = fullfile(cfg.dataDir, 'insar', 'lagos_vlm_s1_2017_2025.tif');
cfg.insarBuffer_m   = 500;   % radar pixels within this distance of the road count for a segment
cfg.insarMinPixels  = 10;    % fewer than this: search 3x wider, then fill from neighbours
cfg.insarDatumSigma = 2.5;   % mm/yr, 1-sigma error of the GPS tie, common to all segments
% A 1 km road segment counts as reached when at least this share of its
% length is under water (10 percent = 100 m). Using the single lowest
% point instead lets one low pixel (a creek, a ditch or a data error)
% decide the whole kilometre.
cfg.segmentWetShare = 0.10;
% Water levels at which the flood-level map is built (metres)
cfg.floodLevels = 0:0.05:6;

% Pixel connectivity for flooding: 8 lets water pass corner to corner,
% 4 only through edges (more conservative).
cfg.connectivity = 8;
end
