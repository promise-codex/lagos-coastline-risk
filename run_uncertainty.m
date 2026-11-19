%RUN_UNCERTAINTY Step 5: Monte Carlo uncertainty for the full method (M3 with M2).
%   Each of N runs draws:
%     u      a sea-level quantile, the same through time (AR6 5th to 95th
%            percentile curves, linear between them; outside 5-95 is not sampled)
%     s      land motion of every elevation cell: the radar map
%            (sinking_field) plus two errors,
%              a GPS tie error, normal with sd cfg.insarDatumSigma, the
%              same for every cell (it shifts the whole map), and
%              a local error, z * sigma(x), with one normal z per run for
%              all cells (fully correlated: the cautious choice, because
%              it widens the spread of the km totals)
%     B      Bruun factor, uniform between 0 and 100
%   and finds, for every road km, whether it is reached by 2050 and by
%   2100 by the ordinary high tide (MHHW, open sea), by the mean level of
%   any water (lagoon included), or by erosion. Flooding is run on the
%   whole elevation model with each cell moved at its own rate
%   (fullmap_first_years), only for the years 2050 and 2100 to keep the
%   2000 runs to about 15 minutes per scenario.
%
%   Erosion is computed with the closed-form solution of the Simulink
%   shoreline model (valid because D = 0, so each km evolves on its own):
%       retreat(t) = -min(r,0) (t - 2020) + B * integral of max(rate - hist, 0)
%   The script first checks this formula against one Simulink run.
%
%   Needs: run_m3_extremes and run_m2_shoreline run first.

cfg = project_config();
N = 2000;
rng(2026);                                              % repeatable draws
T3 = readtable(fullfile(cfg.resultsDir, 'm3_road_first_wet_year.csv'));
T2 = readtable(fullfile(cfg.resultsDir, 'm2_ladder_by_km.csv'));
[Z, M, R] = load_dem(cfg);
road = road_cells(cfg, R, M);
[V, Sg] = sinking_field(cfg, R, size(Z));
[~, lonGrid] = geographicGrid(R);
G  = readtable(fullfile(cfg.dataDir, 'gtsm', 'gtsm_lagos_stations.csv'));
nSeg = height(T3);
[~, nearest] = min(abs(T3.lon_mid - G.lon'), [], 2);
mhhw = G.MHHW_m(nearest);
lvlAny = T3.flood_level_any_m;
lvlOcean = T3.flood_level_ocean_m;
dist = T2.dist_to_shore_m;
r = min(T2.measured_rate_m_yr, 0);
erosionKnown = ~isnan(r) & ~isnan(dist);
r(~erosionKnown) = 0;
years = cfg.years; t0 = cfg.refYear;
histRate = 0.00325;

% ---- AR6 quantile curves --------------------------------------------------------
C = readcell(cfg.slrFile, 'Sheet', 'Total');
hdr = C(1, :);
yearCols = find(cellfun(@(x) isnumeric(x) && ~isempty(x) && x > 1900, hdr));
arYears = cell2mat(hdr(yearCols));
q = [5 17 50 83 95];
scen = {'ssp245', 'ssp585'};

% ---- Check the closed form against the Simulink model ---------------------------
Qc = zeros(numel(q), numel(years));
for i = 1:numel(q)
    row = find(strcmp(C(:, 3), 'medium') & strcmp(C(:, 4), 'ssp245') & ...
               cellfun(@(x) isnumeric(x) && isequal(x, q(i)), C(:, 5)));
    Qc(i, :) = interp1(arYears, cell2mat(C(row, yearCols)), years);
end
rate = max(gradient(Qc(3, :), years) - histRate, 0);
in = Simulink.SimulationInput('shoreline_model');
in = in.setVariable('nSeg', nSeg); in = in.setVariable('eprVec', r);
in = in.setVariable('extraRiseRate', [years(:) rate(:)]);
in = in.setVariable('bruunFactor', 50); in = in.setVariable('diffMatrix', zeros(nSeg));
out = sim(in);
closed = -(r' .* (out.tout - t0)) + 50 * interp1(years, cumtrapz(years, rate), out.tout);
fprintf('Closed form vs Simulink: largest difference %.3f m in retreat over 130 years\n', ...
    max(abs(-out.yOut - closed), [], 'all'));

% ---- Monte Carlo ------------------------------------------------------------------
for sc = 1:numel(scen)
    Q = zeros(numel(q), numel(years));
    for i = 1:numel(q)
        row = find(strcmp(C(:, 3), 'medium') & strcmp(C(:, 4), scen{sc}) & ...
                   cellfun(@(x) isnumeric(x) && isequal(x, q(i)), C(:, 5)));
        Q(i, :) = interp1(arYears, cell2mat(C(row, yearCols)), years);
    end
    u = 0.05 + 0.90 * rand(N, 1);
    datum = cfg.insarDatumSigma * randn(N, 1);             % mm/yr, common to all km
    zLoc = randn(N, 1);                                      % local error, in units of sigma
    s = datum + zLoc * 1000 * median(Sg(road.idx));          % summary of the sinking draw, for the ranking below
    [~, nnG] = min(abs(lonGrid(1, :)' - G.lon'), [], 2);
    Etide = G.MHHW_m(nnG)';                                  % high tide per grid column
    yrsMC = [2050 2100];
    tic
    B = 100 * rand(N, 1);
    firstYr = inf(N, nSeg);
    for n = 1:N
        slr = interp1(q / 100, Q, u(n));                       % 1 x years
        Vn = V + single(datum(n) / 1000) + single(zLoc(n)) * Sg;         % m/yr, every cell
        hMC = interp1(years, slr - slr(years == t0), yrsMC);
        [lagoonYr, tideYr] = fullmap_first_years(Z, M, Vn, yrsMC, hMC, t0, Etide, cfg, road);
        extra = max(gradient(slr, years) - histRate, 0);
        retreat = -r .* (years - t0) + B(n) * cumtrapz(years, extra);   % nSeg x years
        eroYr = inf(nSeg, 1);
        for k = find(erosionKnown)'
            j = find(retreat(k, :) >= dist(k), 1);
            if ~isempty(j), eroYr(k) = years(j); end
        end
        firstYr(n, :) = min([tideYr, lagoonYr, eroYr], [], 2)';
        if mod(n, 250) == 0, fprintf('  %s: %d of %d runs (%.0f s)\n', scen{sc}, n, N, toc); end
    end
    p2050 = mean(firstYr <= 2050, 1)';
    p2100 = mean(firstYr <= 2100, 1)';
    km2050 = sum(firstYr <= 2050, 2);
    km2100 = sum(firstYr <= 2100, 2);
    fprintf('\n%s, %d runs: road km reached (median and 5-95%% range)\n', scen{sc}, N);
    fprintf('  by 2050: %d  (%d to %d)\n', round(median(km2050)), round(prctile(km2050, 5)), round(prctile(km2050, 95)));
    fprintf('  by 2100: %d  (%d to %d)\n', round(median(km2100)), round(prctile(km2100, 5)), round(prctile(km2100, 95)));
    fprintf('  km with at least 50%% chance of being reached by 2050: %d; by 2100: %d\n', ...
        sum(p2050 >= 0.5), sum(p2100 >= 0.5));
    [~, iS] = sort(abs(corr([u s B], km2100, 'Type', 'Spearman')), 'descend');
    names = {'sea-level quantile', 'sinking error (GPS tie + radar)', 'Bruun factor'};
    fprintf('  what drives the 2100 result most (rank correlation): %s, then %s, then %s\n', names{iS});

    T = T3(:, {'segment', 'start_km', 'end_km', 'lat_mid', 'lon_mid'});
    T.p_reached_by_2050 = p2050; T.p_reached_by_2100 = p2100;
    writetable(T, fullfile(cfg.resultsDir, sprintf('uncertainty_%s.csv', scen{sc})));

    fig = figure('Color', 'w', 'Position', [100 100 1100 380]);
    ax = axes(fig);
    bar(ax, T.start_km + 0.5, [p2050 p2100], 1, 'grouped');
    ylim(ax, [0 1]); grid(ax, 'on');
    legend(ax, {'by 2050', 'by 2100'}, 'Location', 'northeast');
    xlabel(ax, 'Chainage along the highway (km)');
    ylabel(ax, 'Chance the route is reached');
    title(ax, sprintf(['Chance each road km is reached by high tide, lagoon level or erosion ' ...
        '(%s, %d runs)'], scen{sc}, N));
    exportgraphics(fig, fullfile(cfg.figDir, sprintf('uncertainty_%s.png', scen{sc})), 'Resolution', 200);
end
fprintf('\nSaved results/uncertainty_*.csv and figures/uncertainty_*.png\n');

% -------------------------------------------------------------------------
function yr = yearReached(needed, h, years)
% First year the non-decreasing curve h reaches each level (Inf if never).
% h: one row for everywhere, or one row per level in needed
if isvector(h), h = h(:)'; end
idx = sum(h < needed(:), 2) + 1;                      % count of years below the level
yr = inf(numel(needed), 1);
ok = idx <= numel(years) & ~isnan(needed(:));
yr(ok) = years(idx(ok));
yr(isnan(needed(:))) = Inf;
end
