%RUN_M2_SHORELINE Step 4: moving beach (M2) with a Simulink shoreline model, and the full method ladder.
%   Shoreline change per road km comes from the highway assessment's own
%   measured end point rates (Section 1 pp. 4-60 to 4-61 by chainage band,
%   Section 2 p. 4-89 by community). The Simulink model shoreline_model.slx
%   (built by build_shoreline_model.m) moves the shoreline forward in time:
%       dy/dt = r - B * s(t) + D * L * y
%   r = measured rate (accretion set to 0: past gains came mostly from port
%   and reclamation sand fill and are not extrapolated), s(t) = sea-level
%   rise rate above the historical rate, B = Bruun factor.
%
%   The road km is "reached by erosion" in the first year the shoreline
%   has moved back by the distance between today's shoreline and the
%   closest 10% of that km. The ladder then combines:
%     M0  bathtub, mean sea level only            (from run_m3_extremes)
%     M1  + land sinking, measured by radar per km (from run_m3_extremes)
%     M2  + moving beach: earlier of M1 and erosion
%     M3  + high tide / 10-year storm: earlier of M3 and erosion
%
%   Needs: run_m1_sinking and run_m3_extremes run first, and get_place_coords.

cfg = project_config();
S = load(fullfile(cfg.resultsDir, 'flood_level_map.mat'), 'M', 'R');
M = S.M; R = S.R;
H = load(fullfile(cfg.osmDir, 'highway_segments.mat'), 'segs', 'samples');
segs = H.segs; nSeg = height(segs);
midKm = (segs.start_km + segs.end_km) / 2;

% ---- 1. Distance from today's shoreline to the road ------------------------
cellA = cell_area_km2(R);
cellM = 1000 * sqrt(mean(cellA(:)));
distOcean = double(bwdist(M == 1)) * cellM;                      % metres to nearest ocean cell
[I, J] = geographicToDiscrete(R, H.samples.lat, H.samples.lon);
use = ~isnan(I) & ~isnan(J) & H.samples.mapped(:);
d = distOcean(sub2ind(size(M), I(use), J(use)));
segOf = discretize(H.samples.chainage_km(use), [segs.start_km; segs.end_km(end)]);
segDist = accumarray(segOf, d, [nSeg 1], @(x) prctile(x, 10), NaN);

% ---- 2. Measured shoreline change rate per road km --------------------------
epr = nan(nSeg, 1); eprSource = strings(nSeg, 1);
B1 = readtable(fullfile(cfg.dataDir, 'esia', 'shoreline_rates_section1.csv'));
for k = 1:nSeg
    if midKm(k) < 47.5
        % band covering most of this km (first listed band wins a tie)
        ov = max(0, min(segs.end_km(k), B1.to_km) - max(segs.start_km(k), B1.from_km));
        [best, b] = max(ov);
        if best < 0.25, b = []; end                                  % less than 250 m covered
        if ~isempty(b) && ~isnan(B1.epr_used_m_yr(b))
            epr(k) = B1.epr_used_m_yr(b);
            eprSource(k) = sprintf('S1 p.%s, CH %.1f-%.1f', string(B1.page(b)), B1.from_km(b), B1.to_km(b));
        end
    end
end
P = readtable(fullfile(cfg.osmDir, 'places.csv'), 'TextType', 'string');
P = P(~isnan(P.lon), :);
for k = find(midKm >= 47.5)'
    [~, j] = min(abs(P.lon - segs.lon_mid(k)));
    epr(k) = P.epr_m_yr(j);
    eprSource(k) = "S2 p.4-89, " + P.community(j);
end
known = ~isnan(epr);
rUsed = min(epr, 0); rUsed(~known) = 0;
fprintf('Measured rates assigned to %d of %d road km (others: no usable rate in the assessment).\n', ...
    sum(known), nSeg);

% ---- 3. Extra sea-level rise rate ---------------------------------------------
% The measured shoreline trend (1984-2024) already includes the rise that
% happened then, and any land sinking. Only the rise ABOVE the historical
% rate is added through the Bruun term. Historical rate: global mean
% 1993-2018, 3.25 mm/yr (IPCC AR6 WG1 Ch. 9); a local tide-gauge rate for
% Lagos over that period is not available to this project.
histRate = 0.00325;
C = readcell(cfg.slrFile, 'Sheet', 'Total');
hdr = C(1, :);
yearCols = find(cellfun(@(x) isnumeric(x) && ~isempty(x) && x > 1900, hdr));
arYears = cell2mat(hdr(yearCols));
cases = {'medium', 'ssp245', 50; 'medium', 'ssp585', 50};
bruun = [0 50 100];        % 0 = trend only; 50 and 100 m of retreat per m of extra rise
L = spdiags(ones(nSeg, 1) * [1 -2 1], -1:1, nSeg, nSeg);
L(1, 1) = -1; L(end, end) = -1;                          % closed ends
D = 0;                                                   % no calibrated alongshore value here
diffMatrix = full(D / 1000^2 * L);

if ~isfile(fullfile(cfg.root, 'shoreline_model.slx'))
    build_shoreline_model();
end
load_system('shoreline_model');
erosionYear = cell(size(cases, 1), numel(bruun));
retreat2100 = cell(size(cases, 1), numel(bruun));
for c = 1:size(cases, 1)
    row = find(strcmp(C(:, 3), cases{c, 1}) & strcmp(C(:, 4), cases{c, 2}) & ...
               cellfun(@(x) isnumeric(x) && isequal(x, cases{c, 3}), C(:, 5)));
    slr = interp1(arYears, cell2mat(C(row, yearCols)), cfg.years);
    rate = max(gradient(slr, cfg.years) - histRate, 0);
    for b = 1:numel(bruun)
        in = Simulink.SimulationInput('shoreline_model');
        in = in.setVariable('nSeg', nSeg);
        in = in.setVariable('eprVec', rUsed);
        in = in.setVariable('extraRiseRate', [cfg.years(:) rate(:)]);
        in = in.setVariable('bruunFactor', bruun(b));
        in = in.setVariable('diffMatrix', diffMatrix);
        out = sim(in);
        t = out.tout; y = out.yOut;                      % y: time x segment
        yr = inf(nSeg, 1);
        for k = 1:nSeg
            if ~known(k) || isnan(segDist(k)), yr(k) = NaN; continue, end
            hit = find(-y(:, k) >= segDist(k), 1);
            if ~isempty(hit), yr(k) = round(t(hit)); end
        end
        erosionYear{c, b} = yr;
        retreat2100{c, b} = -interp1(t, y, 2100)';
    end
end

% ---- 4. Check against the assessment's own erosion forecast -----------------
% Section 1 p. 4-62: erosion reaches the road within 10 to 20 years (2034-2044)
% at CH 3+800, CH 12+400 to 12+900 and CH 33+600 to 37+500.
fprintf('\nAssessment forecast check (SSP2-4.5, trend only, B = 0):\n');
chk = [3.8 3.8; 12.4 12.9; 33.6 37.5];
for i = 1:size(chk, 1)
    k = find(segs.end_km > chk(i, 1) & segs.start_km < chk(i, 2));
    fprintf('  CH %.1f-%.1f km: distance to shore %s m; rate %s m/yr; erosion reaches road in %s\n', ...
        chk(i, 1), chk(i, 2), mat2str(round(segDist(k))'), mat2str(epr(k)'), mat2str(erosionYear{1, 1}(k)'));
end

% ---- 5. Method ladder ----------------------------------------------------------
T3 = readtable(fullfile(cfg.resultsDir, 'm3_road_first_wet_year.csv'));
v = T3.Properties.VariableNames;
col = @(a, b) T3.(v{contains(v, 'ssp245') & contains(v, a) & contains(v, b)});
sinkTag = 'sinkInSARmm';                                 % measured radar sinking per km
M0 = col('MeanSeaLevel', 'sink0mm');
M1 = col('MeanSeaLevel', sinkTag);
M3tide  = col('MHHW', sinkTag);
M3storm = col('10_year', sinkTag);
ero = erosionYear{1, 2};                                  % SSP2-4.5, B = 50
ero(isnan(ero)) = Inf;
M2 = min(M1, ero);
M3t = min(M3tide, ero);
M3s = min(M3storm, ero);

ladder = {'M0 bathtub (assessment approach)', M0; ...
          'M1 + measured sinking (radar)', M1; ...
          'M2 + moving beach (B = 50)', M2; ...
          'M3 + ordinary high tide', M3t; ...
          'M3 + 10-year storm', M3s};
fprintf('\nMethod ladder, SSP2-4.5 median: road km reached\n');
fprintf('%-36s %6s %8s %8s %8s %8s\n', 'Method', 'today', 'by 2030', 'by 2050', 'by 2100', 'first');
for i = 1:size(ladder, 1)
    yv = ladder{i, 2};
    f = min(yv); if isinf(f), fs = 'none'; else, fs = sprintf('%d', f); end
    fprintf('%-36s %6d %8d %8d %8d %8s\n', ladder{i, 1}, sum(yv <= cfg.refYear), sum(yv <= 2030), ...
        sum(yv <= 2050), sum(yv <= 2100), fs);
end

fprintf('\nErosion alone (road km reached by 2100):\n');
for c = 1:size(cases, 1)
    for b = 1:numel(bruun)
        e = erosionYear{c, b};
        fprintf('  %s, Bruun %3d: %d km by 2050, %d km by 2100; median retreat by 2100 %.0f m\n', ...
            cases{c, 2}, bruun(b), sum(e <= 2050), sum(e <= 2100), median(retreat2100{c, b}(known)));
    end
end

out2 = segs(:, {'segment', 'start_km', 'end_km', 'lat_mid', 'lon_mid'});
out2.dist_to_shore_m = segDist; out2.measured_rate_m_yr = epr; out2.rate_source = eprSource;
out2.erosion_year_ssp245_trend = erosionYear{1, 1};
out2.erosion_year_ssp245_bruun50 = erosionYear{1, 2};
out2.erosion_year_ssp245_bruun100 = erosionYear{1, 3};
out2.M0 = M0; out2.M1 = M1; out2.M2 = M2; out2.M3_tide = M3t; out2.M3_storm10 = M3s;
writetable(out2, fullfile(cfg.resultsDir, 'm2_ladder_by_km.csv'));

fig = figure('Color', 'w', 'Position', [100 100 1100 460]);
ax = axes(fig); hold(ax, 'on');
cols = lines(size(ladder, 1));
% Different shapes and sizes so a method that gives the same year as the
% one before it (often M1 and M2) still shows: larger open markers behind,
% smaller filled markers in front.
mk = {'o', 'o', '.', 'd', 's'}; ms = [5 9 12 5 5]; filled = [true false true true true];
for i = 1:size(ladder, 1)
    if filled(i), fc = cols(i, :); else, fc = 'none'; end
    plot(ax, midKm, ladder{i, 2}, mk{i}, 'Color', cols(i, :), 'MarkerFaceColor', fc, ...
        'MarkerSize', ms(i), 'LineWidth', 1.2, 'DisplayName', ladder{i, 1});
end
hold(ax, 'off'); grid(ax, 'on');
ylim(ax, [cfg.refYear max(cfg.years)]);
xlabel(ax, 'Chainage along the highway (km)');
ylabel(ax, 'First year the route is reached');
title(ax, 'Method ladder for the Lagos coastal highway (AR6 SSP2-4.5 median)');
legend(ax, 'Location', 'southoutside', 'NumColumns', 3);
exportgraphics(fig, fullfile(cfg.figDir, 'method_ladder_full.png'), 'Resolution', 200);
fprintf('\nSaved results/m2_ladder_by_km.csv and figures/method_ladder_full.png\n');
