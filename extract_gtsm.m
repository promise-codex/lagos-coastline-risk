%EXTRACT_GTSM Rebuild data/gtsm/gtsm_lagos_stations.csv from the Copernicus NetCDF files.
%   Put the downloaded files (reanalysis_waterlevel_actual-value_1985-2014_rpN_*.nc
%   and historical_tide_actual-value_1985-2014_MHHW_v1.nc) in data/gtsm/nc,
%   then run this script. It keeps the GTSM points along the Lagos coast.
%   Note: the 95% upper bounds of the return levels at these points are
%   unrealistically large (tens of metres) from the bootstrap fit, so only
%   the best fit is used in the analysis; the bounds are kept for reference.

cfg = project_config();
ncDir = fullfile(cfg.dataDir, 'gtsm', 'nc');
mh = dir(fullfile(ncDir, '*MHHW*.nc'));
f0 = fullfile(mh(1).folder, mh(1).name);
lon = ncread(f0, 'station_x_coordinate');
lat = ncread(f0, 'station_y_coordinate');
MHHW = ncread(f0, 'MHHW');
sel = find(lon > 3.15 & lon < 4.6 & lat > 6.2 & lat < 6.5);
[~, o] = sort(lon(sel)); sel = sel(o);

T = table(sel - 1, round(lon(sel), 4), round(lat(sel), 4), round(double(MHHW(sel)), 3), ...
    'VariableNames', {'station_index', 'lon', 'lat', 'MHHW_m'});   % index counted from 0
rps = [1 2 5 10 25 50 75 100];
kinds = {'best-fit', '', 'return_mean_water_level'; ...
         'low-bound', '_low5', 'return_5_water_level'; ...
         'high-bound', '_high95', 'return_95_water_level'};
for k = 1:size(kinds, 1)
    for p = rps
        f = dir(fullfile(ncDir, sprintf('*_rp%d_%s*.nc', p, kinds{k, 1})));
        v = ncread(fullfile(f(1).folder, f(1).name), kinds{k, 3});
        T.(sprintf('rp%d%s_m', p, kinds{k, 2})) = round(v(sel), 3);
    end
end
writetable(T, fullfile(cfg.dataDir, 'gtsm', 'gtsm_lagos_stations.csv'));
disp(T(:, 1:8))
