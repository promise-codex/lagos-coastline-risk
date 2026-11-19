%RUN_M3_EXTREMES Add high tide and storm water levels on top of M1.
%   Extra water level above mean sea level, per stretch of coast, from the
%   Copernicus dataset "Global sea level change indicators from 1950 to
%   2050" (GTSM v3 forced by ERA5, 1985-2014, CC BY; DOI 10.24381/cds.6edf04e0):
%     MHHW   mean higher high water (an ordinary high tide)
%     rpN    total water level (tide + surge) reached on average once every N years
%   These are heights above the 1986-2005 mean sea level. They are treated
%   as heights above the mean sea level of each future year, i.e. tides and
%   storms are assumed not to change; only the mean level rises.
%
%   Water at the road in year t for event E:
%       h(t) + E,   h(t) = [SLR(t) - SLR(refYear)] + s * (t - refYear)
%   A segment is reached when h(t) + E >= its flood level, i.e. when
%   h(t) >= flood level - E, so the M1 machinery is reused with a shifted level.
%
%   Needs: results/flood_level_map.mat (made by run_m1_sinking) and
%   data/gtsm/gtsm_lagos_stations.csv (coastal GTSM points from the
%   downloaded NetCDF files; see extract_gtsm.m to rebuild it).

cfg = project_config();
S = load(fullfile(cfg.resultsDir, 'flood_level_map.mat'), 'FL', 'R');
FL = S.FL; R = S.R;

% ---- AR6 curves (same as step 2) ---------------------------------------------
C = readcell(cfg.slrFile, 'Sheet', 'Total');
hdr = C(1, :);
yearCols = find(cellfun(@(x) isnumeric(x) && ~isempty(x) && x > 1900, hdr));
arYears = cell2mat(hdr(yearCols));
cases = {'medium', 'ssp245', 50; 'medium', 'ssp585', 50};
slr = zeros(size(cases, 1), numel(cfg.years));
for c = 1:size(cases, 1)
    row = find(strcmp(C(:, 3), cases{c, 1}) & strcmp(C(:, 4), cases{c, 2}) & ...
               cellfun(@(x) isnumeric(x) && isequal(x, cases{c, 3}), C(:, 5)));
    slr(c, :) = interp1(arYears, cell2mat(C(row, yearCols)), cfg.years);
end

% ---- Extreme water levels per road segment (nearest GTSM point) -------------
G = readtable(fullfile(cfg.dataDir, 'gtsm', 'gtsm_lagos_stations.csv'));
events = {'Mean sea level', zeros(height(G), 1); ...
          'High tide (MHHW)', G.MHHW_m; ...
          '1-year storm',   G.rp1_m; ...
          '10-year storm',  G.rp10_m; ...
          '100-year storm', G.rp100_m};
nEv = size(events, 1);

H = load(fullfile(cfg.osmDir, 'highway_segments.mat'), 'segs', 'samples');
[I, J] = geographicToDiscrete(R, H.samples.lat, H.samples.lon);
use = ~isnan(I) & ~isnan(J) & H.samples.mapped(:);
fl = double(FL(sub2ind(size(FL), I(use), J(use))));   % NaN over water (bridges) is ignored
segOf = discretize(H.samples.chainage_km(use), [H.segs.start_km; H.segs.end_km(end)]);
nSeg = height(H.segs);
segLevel = accumarray(segOf, fl, [nSeg 1], @min, NaN);
[~, nearest] = min(abs(H.segs.lon_mid - G.lon'), [], 2);   % nearest point along the coast

% ---- First year reached ----------------------------------------------------------
rates = cfg.subsidence_mm_yr;
out = H.segs(:, {'segment', 'start_km', 'end_km', 'lat_mid', 'lon_mid'});
out.ground_level_m = segLevel;
fprintf('\nRoad segments (of %d) reached by the water, AR6 median\n', sum(~isnan(segLevel)));
fprintf('%-8s %-18s %-11s %6s %8s %8s %8s %8s\n', 'Scenario', 'Event', 'Sinking', 'today', 'by 2030', 'by 2050', 'by 2100', 'first');
firstYr = cell(size(cases, 1), nEv, numel(rates));
for c = 1:size(cases, 1)
    for e = 1:nEv
        E = events{e, 2}(nearest);
        for r = 1:numel(rates)
            h = (slr(c, :) - slr(c, cfg.years == cfg.refYear)) + rates(r) / 1000 * (cfg.years - cfg.refYear);
            yr = firstYearReached(segLevel - E, h, cfg.years);
            firstYr{c, e, r} = yr;
            name = matlab.lang.makeValidName(sprintf('year_%s_%s_sink%smm', cases{c, 2}, ...
                events{e, 1}, strrep(sprintf('%g', rates(r)), '.', 'p')));
            out.(name) = yr;
            fprintf('%-8s %-18s %5.1f mm/yr %6d %8d %8d %8d %8s\n', cases{c, 2}, events{e, 1}, rates(r), ...
                sum(yr <= cfg.refYear), sum(yr <= 2030), sum(yr <= 2050), sum(yr <= 2100), yearText(min(yr)));
        end
    end
end
writetable(out, fullfile(cfg.resultsDir, 'm3_road_first_wet_year.csv'));

% ---- Figure: the method ladder along the road (SSP2-4.5) ---------------------
rMid = find(rates == 11.4, 1); if isempty(rMid), rMid = min(2, numel(rates)); end
ladder = {'M0: mean sea level, no sinking',              1, 1; ...
          sprintf('M1: + sinking %g mm/yr', rates(rMid)), 1, rMid; ...
          'M3: + high tide (MHHW)',                      2, rMid; ...
          'M3: + 10-year storm',                         4, rMid};
fig = figure('Color', 'w', 'Position', [100 100 1100 450]);
ax = axes(fig); hold(ax, 'on');
cols = lines(size(ladder, 1));
for k = 1:size(ladder, 1)
    yr = firstYr{1, ladder{k, 2}, ladder{k, 3}};
    plot(ax, out.start_km + 0.5, yr, 'o', 'Color', cols(k, :), 'MarkerFaceColor', cols(k, :), ...
        'MarkerSize', 4, 'DisplayName', ladder{k, 1});
end
hold(ax, 'off');
ylim(ax, [cfg.refYear max(cfg.years)]); grid(ax, 'on');
xlabel(ax, 'Chainage along the highway (km)');
ylabel(ax, 'First year the water reaches the route');
title(ax, 'Each added process brings the first wet year forward (AR6 SSP2-4.5 median)');
legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal');
exportgraphics(fig, fullfile(cfg.figDir, 'm3_method_ladder.png'), 'Resolution', 200);
fprintf('\nSaved results/m3_road_first_wet_year.csv and figures/m3_method_ladder.png\n');

% -------------------------------------------------------------------------
function yr = firstYearReached(needed, h, years)
yr = inf(size(needed));
for i = 1:numel(needed)
    if isnan(needed(i)), yr(i) = NaN; continue, end
    k = find(h >= needed(i), 1);
    if ~isempty(k), yr(i) = years(k); end
end
end

function t = yearText(y)
if isinf(y) || isnan(y), t = 'none'; else, t = sprintf('%d', y); end
end
