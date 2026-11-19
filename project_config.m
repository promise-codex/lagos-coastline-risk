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

% Pixel connectivity for flooding: 8 lets water pass corner to corner,
% 4 only through edges (more conservative).
cfg.connectivity = 8;
end
