%RUN_ASSETS Step 8: the Dangote refinery and the Lekki Deep Sea Port.
%   The same flood methods as for the road, applied to the land inside each
%   site outline from OpenStreetMap (data/osm/osm_features.mat, made by
%   get_osm_features):
%     M0  bathtub, no sinking
%     M1  mean sea level with the measured land motion (radar map), cell by cell
%     M3  M1 plus high tide, and plus a 10-year storm (open sea only)
%   For SSP2-4.5 and SSP5-8.5 (AR6 median) the script gives the first year
%   in which 1% and 10% of each site's land is under water.
%
%   IMPORTANT, elevation data age: DeltaDTM is built on the Copernicus DEM,
%   whose radar data were taken in 2011-2015. The refinery site was filled
%   and the port was built after that, so the elevation model may show the
%   ground from BEFORE the fill. The script prints the heights inside each
%   outline so this can be judged. If the outline is mostly at 0-1 m or
%   marked as water, the results describe the original ground, not the
%   finished site, and must not be read as a forecast for the site itself.
%
%   Outputs: results/assets_first_years.csv and results/figures/assets_map.png.
%   About 5 minutes.

cfg = project_config();
[Z, M, R] = load_dem(cfg);
[V, ~] = sinking_field(cfg, R, size(Z));
F = load(fullfile(cfg.osmDir, 'osm_features.mat'), 'features'); F = F.features;

% ---- 1. Pick one outline per site: the largest closed area matching the name ---------------
sites = {'Dangote site', 'Dangote'; 'Lekki Deep Sea Port', 'Lekki Deep|Lekki Port|Deep Sea Port'};
lat0 = mean(cfg.latlim); mx = 111320 * cosd(lat0); my = 110570;
fprintf('Candidate outlines from OpenStreetMap:\n');
pick = zeros(size(sites, 1), 1); areaHa = nan(size(sites, 1), 1);
for s = 1:size(sites, 1)
    best = 0;
    for k = 1:numel(F)
        if isempty(regexpi(F(k).name, sites{s, 2}, 'once')) || startsWith(F(k).kind, 'highway'), continue, end
        la = F(k).lat(~isnan(F(k).lat)); lo = F(k).lon(~isnan(F(k).lon));
        if numel(la) < 4, continue, end
        a = polyarea(lo * mx, la * my) / 1e4;                 % ha
        fprintf('  %-22s %-9s %12d  %-40s %8.1f ha\n', sites{s, 1}, F(k).type, F(k).id, F(k).name, a);
        if a > best, best = a; pick(s) = k; end
    end
    areaHa(s) = best;
end

% ---- 2. Cells inside each outline -------------------------------------------------------------
asset.idx = []; asset.seg = [];
for s = 1:size(sites, 1)
    if pick(s) == 0, warning('run_assets:none', 'No outline found for %s', sites{s, 1}); continue, end
    la = F(pick(s)).lat(~isnan(F(pick(s)).lat)); lo = F(pick(s)).lon(~isnan(F(pick(s)).lon));
    [xI, yI] = geographicToIntrinsic(R, la, lo);
    inside = poly2mask(xI, yI, size(Z, 1), size(Z, 2));
    id = find(inside);
    asset.idx = [asset.idx; id]; asset.seg = [asset.seg; s * ones(numel(id), 1)];
    z = Z(id); land = M(id) == 0;
    fprintf('\n%s (OSM %s %d, %.0f ha, %d cells):\n', sites{s, 1}, F(pick(s)).type, F(pick(s)).id, areaHa(s), numel(id));
    fprintf('  marked as water in the elevation model: %.0f%% of cells\n', 100 * mean(~land));
    fprintf('  land height (m above EGM2008): 10th %.2f, median %.2f, 90th %.2f; below 1 m: %.0f%%\n', ...
        prctile(z(land), 10), median(z(land)), prctile(z(land), 90), 100 * mean(z(land) < 1));
    fprintf('  measured land motion: median %.1f mm/yr\n', 1000 * median(V(id(land))));
end
keepLand = M(asset.idx) == 0;
asset.idx = asset.idx(keepLand); asset.seg = asset.seg(keepLand);
asset.nSeg = size(sites, 1);
asset.nLand = accumarray(asset.seg, 1, [asset.nSeg 1]);

% ---- 3. First year 1% and 10% of each site is under water -------------------------------------
C = readcell(cfg.slrFile, 'Sheet', 'Total');
hdr = C(1, :);
yearCols = find(cellfun(@(x) isnumeric(x) && ~isempty(x) && x > 1900, hdr));
arYears = cell2mat(hdr(yearCols));
years = cfg.years; t0 = cfg.refYear;
G = readtable(fullfile(cfg.dataDir, 'gtsm', 'gtsm_lagos_stations.csv'));
[~, lonGrid] = geographicGrid(R);
[~, nn] = min(abs(lonGrid(1, :)' - G.lon'), [], 2);
Ecols = [G.MHHW_m(nn)'; G.rp10_m(nn)'];
scen = {'ssp245', 'ssp585'}; shares = [0.01 0.10];
rows = {};
for sc = 1:numel(scen)
    row = find(strcmp(C(:, 3), 'medium') & strcmp(C(:, 4), scen{sc}) & ...
               cellfun(@(x) isnumeric(x) && isequal(x, 50), C(:, 5)));
    v = interp1(arYears, cell2mat(C(row, yearCols)), years); h = v - v(years == t0);
    for sh = shares
        c2 = cfg; c2.segmentWetShare = sh;
        y0 = fullmap_first_years(Z, M, single(0), years, h, t0, zeros(1, numel(nn)), c2, asset);
        [y1, yE] = fullmap_first_years(Z, M, V, years, h, t0, Ecols, c2, asset);
        for s = 1:asset.nSeg
            rows(end + 1, :) = {sites{s, 1}, scen{sc}, 100 * sh, y0(s), y1(s), yE(s, 1), yE(s, 2)}; %#ok<SAGROW>
        end
    end
end
T = cell2table(rows, 'VariableNames', {'site', 'scenario', 'share_pct', 'M0_bathtub', 'M1_measured_sinking', ...
    'M3_high_tide', 'M3_10yr_storm'});
writetable(T, fullfile(cfg.resultsDir, 'assets_first_years.csv'));
fprintf('\nFirst year the given share of the site''s land is under water (Inf = not by %d):\n', years(end));
disp(T);

% ---- 4. Map ---------------------------------------------------------------------------------------
fig = figure('Color', 'w', 'Position', [80 80 1100 500]);
gx = geoaxes(fig); geobasemap(gx, 'satellite'); hold(gx, 'on');
cl = lines(asset.nSeg);
for s = 1:asset.nSeg
    if pick(s) == 0, continue, end
    geoplot(gx, F(pick(s)).lat, F(pick(s)).lon, '-', 'Color', cl(s, :), 'LineWidth', 2, 'DisplayName', sites{s, 1});
end
hold(gx, 'off'); legend(gx, 'Location', 'southoutside');
la = vertcat(F(pick(pick > 0)).lat); lo = vertcat(F(pick(pick > 0)).lon);
geolimits(gx, [min(la) max(la)] + [-0.01 0.01], [min(lo) max(lo)] + [-0.02 0.02]);
title(gx, 'Site outlines used (OpenStreetMap)');
exportgraphics(fig, fullfile(cfg.figDir, 'assets_map.png'), 'Resolution', 200);
fprintf('Saved results/assets_first_years.csv and results/figures/assets_map.png\n');
