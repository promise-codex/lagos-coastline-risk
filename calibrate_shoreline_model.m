%CALIBRATE_SHORELINE_MODEL Step 9: calibrate the Simulink shoreline model and test it on later years.
%   Uses our own Landsat shoreline positions (results/shoreline_positions.csv,
%   from extract_shorelines) to calibrate the model of step 4 on the early
%   period, then runs it forward and compares it with the shorelines that
%   were seen later (a hindcast).
%
%   Periods. The plan was 1984-2010 for calibration and 2011-2025 for the
%   test. The Landsat epochs available are 1986 (pooled 1984-1987), 2000,
%   2003, 2005, 2009 (3-year epochs) and every year 2013-2025, plus 2012
%   (the 2010-2012 epoch). So calibration uses 1986-2009 (5 epochs) and the
%   test uses 2012-2025 (14 epochs), started from the 2009 shoreline.
%
%   Model (shoreline_model_cal.slx, built by build_shoreline_model), for the
%   change y since the start year at every road km:
%       dy/dt = r + a * (P(t) - mean P) + D * L * y
%     r   trend per km, fitted to the 1986-2009 positions (robust fit)
%     a   effect of the yearly offshore wave power P (ERA5) on the rate,
%         one value for the whole coast (m/yr per kW/m), fitted
%     D   alongshore smoothing (m^2/yr), one value, fitted; L is the
%         second difference over 1 km with closed ends
%   B (Bruun) is not fitted: the rise in sea level over 1986-2009 is too
%   small and too even to tell it apart from the trend r. Diffusion here
%   acts on the change since the start year, not on the full plan shape of
%   the coast (the road is not straight, so distances from the road are not
%   a straight coastal baseline); this is a simplification.
%
%   Wave power: P = 0.49 * Hs^2 * T (kW/m, deep water), from ERA5 monthly
%   means of significant wave height Hs and mean wave period T at the sea
%   points of data/era5/ (any .nc file there), averaged per year. Squaring a
%   monthly mean Hs underestimates the mean of Hs^2, and the mean period is
%   used for the energy period; both are approximations, and only the
%   year-to-year changes of P are used. Without the ERA5 file, a = 0.
%
%   Test against three simple forecasts over 2012-2025:
%     no change (shoreline stays where it was in 2009),
%     trend only (D = 0, a = 0),
%     the assessment's rates (where it gives one).
%   Skill = 1 - MSE(model) / MSE(no change); above 0 means better than no change.
%   Km flagged as reclaimed land are left out.
%
%   Outputs: results/shoreline_calibration.csv, results/figures/shoreline_hindcast.png.

cfg = project_config();
P = readtable(fullfile(cfg.resultsDir, 'shoreline_positions.csv'));
Rt = readtable(fullfile(cfg.resultsDir, 'shoreline_rates.csv'), 'TextType', 'string');
nSeg = height(P); mid = (P.start_km + P.end_km) / 2;
v = P.Properties.VariableNames;
lc = v(startsWith(v, 'landsat_'));
ly = cellfun(@(x) str2double(extractAfter(x, 'landsat_')), lc);
Y = P{:, lc};                                              % nSeg x epochs, distance road -> shore (m)
built = Rt.flag ~= "" & ~ismissing(Rt.flag);
Y(built, :) = NaN;

cal = ly <= 2010; val = ly >= 2012;
yStart = Y(:, ly == 2009);

% ---- Trend per km from the calibration epochs ------------------------------------------
r = nan(nSeg, 1);
for k = 1:nSeg
    ok = cal & ~isnan(Y(k, :));
    if sum(ok) >= 4 && ~isnan(yStart(k))
        b = robustfit(ly(ok)', Y(k, ok)'); r(k) = b(2);
    end
end
use = ~isnan(r);
fprintf('Calibration 1986-2009: trend fitted at %d of %d km; median %.2f m/yr\n', sum(use), nSeg, median(r(use)));

% ---- Wave power from ERA5 ------------------------------------------------------------------------
waveYears = 1985:2025; Pw = zeros(size(waveYears)); haveWaves = false;
f = dir(fullfile(cfg.dataDir, 'era5', '*.nc'));
if ~isempty(f)
    fn = fullfile(f(1).folder, f(1).name);
    info = ncinfo(fn); names = {info.Variables.Name};
    hs = double(ncread(fn, 'swh')); tm = double(ncread(fn, 'mwp'));
    tname = names{ismember(names, {'valid_time', 'time'})};
    t = ncread(fn, tname); u = ncreadatt(fn, tname, 'units');
    t0 = datetime(regexp(u, '\d{4}-\d{2}-\d{2}', 'match', 'once'));
    if startsWith(u, 'seconds'), tt = t0 + seconds(double(t)); else, tt = t0 + hours(double(t)); end
    hs = reshape(hs, [], numel(tt)); tm = reshape(tm, [], numel(tt));
    sea = all(~isnan(hs), 2);
    pm = 0.49 * mean(hs(sea, :), 1).^2 .* mean(tm(sea, :), 1);            % kW/m, monthly
    for i = 1:numel(waveYears)
        Pw(i) = mean(pm(year(tt) == waveYears(i)), 'omitnan');
    end
    haveWaves = all(~isnan(Pw));
    fprintf('ERA5 waves (%s): %d sea points; yearly wave power %.1f to %.1f kW/m (mean %.1f)\n', ...
        f(1).name, sum(sea), min(Pw), max(Pw), mean(Pw));
else
    fprintf('No ERA5 file in data/era5/: running without the wave term (a = 0).\n');
end
Pa = Pw - mean(Pw);

% ---- Simulink runs ----------------------------------------------------------------------------------
mdl = 'shoreline_model_cal';
if ~isfile(fullfile(cfg.root, [mdl '.slx'])), build_shoreline_model(mdl, true); end
load_system(mdl);
Lm = spdiags(ones(nSeg, 1) * [1 -2 1], -1:1, nSeg, nSeg); Lm(1, 1) = -1; Lm(end, end) = -1;
Lm = full(Lm) / 1000^2;
rUse = r; rUse(~use) = 0;
runModel = @(p, t1, t2) simChange(mdl, nSeg, rUse, p(1) * 1e5, p(2), Lm, waveYears, Pa, t1, t2);

% calibration: fit D (in 1e5 m^2/yr) and a to the change since 1986
obsCal = Y(:, cal) - Y(:, ly == 1986);
calYears = ly(cal);
cost = @(p) misfit(p, runModel, 1986, 2009, calYears, obsCal, use);
lb = [0 -5]; ub = [5 5];                       % D up to 5e5 m^2/yr (stable with a 1-year step)
if ~haveWaves, lb(2) = 0; ub(2) = 0; end
opts = optimoptions('fmincon', 'Display', 'off');
p = fmincon(cost, [0.5 0], [], [], [], [], lb, ub, [], opts);
fprintf('Fitted: D = %.0f m^2/yr, a = %.3f m/yr per kW/m; calibration RMSE %.1f m (trend only: %.1f m)\n', ...
    p(1) * 1e5, p(2), sqrt(cost(p)), sqrt(cost([0 0])));

% ---- Hindcast 2012-2025 from the 2009 shoreline --------------------------------------------------------
obsVal = Y(:, val) - yStart; valYears = ly(val);
[tm, ym] = runModel(p, 2009, 2025);
yModel = interp1(tm, ym, valYears)';
[tt0, yt0] = runModel([0 0], 2009, 2025);
yTrend = interp1(tt0, yt0, valYears)';
rAss = Rt.assessment_rate_m_yr; yAss = rAss .* (valYears - 2009);
ok = use & ~isnan(rAss);
mse = @(Ym, m) mean((Ym(m, :) - obsVal(m, :)).^2, 'all', 'omitnan');
mse0 = mean(obsVal(use, :).^2, 'all', 'omitnan');
fprintf('\nHindcast 2012-2025 (%d km), error in shoreline change since 2009:\n', sum(use));
fprintf('  %-34s %8s %8s\n', 'forecast', 'RMSE (m)', 'skill');
fprintf('  %-34s %8.1f %8.2f\n', 'no change', sqrt(mse0), 0);
fprintf('  %-34s %8.1f %8.2f\n', 'trend only (D = 0, a = 0)', sqrt(mse(yTrend, use)), 1 - mse(yTrend, use) / mse0);
fprintf('  %-34s %8.1f %8.2f\n', 'calibrated model', sqrt(mse(yModel, use)), 1 - mse(yModel, use) / mse0);
m0a = mean(obsVal(ok, :).^2, 'all', 'omitnan');
fprintf('  on the %d km with an assessment rate: no change %.1f, assessment rate %.1f, calibrated model %.1f m\n', ...
    sum(ok), sqrt(m0a), sqrt(mse(yAss, ok)), sqrt(mse(yModel, ok)));
endErr = yModel(:, end) - obsVal(:, end);
fprintf('  2025 error of the calibrated model: median %.1f m, 90%% of km within %.0f m\n', ...
    median(endErr(use), 'omitnan'), prctile(abs(endErr(use)), 90));

T = P(:, {'segment', 'start_km', 'end_km'});
T.trend_1986_2009_m_yr = r; T.observed_change_2009_2025_m = obsVal(:, end);
T.model_change_2009_2025_m = yModel(:, end); T.trend_only_change_2009_2025_m = yTrend(:, end);
writetable(T, fullfile(cfg.resultsDir, 'shoreline_calibration.csv'));
cal_D = p(1) * 1e5; cal_a = p(2); %#ok<NASGU>
save(fullfile(cfg.resultsDir, 'shoreline_calibration.mat'), 'cal_D', 'cal_a', 'r');

fig = figure('Color', 'w', 'Position', [80 80 1150 430]);
ax = axes(fig); hold(ax, 'on');
plot(ax, mid(use), obsVal(use, end), 'ko', 'MarkerFaceColor', [0.2 0.2 0.2], 'MarkerSize', 4, 'DisplayName', 'observed (Landsat)');
plot(ax, mid(use), yModel(use, end), '-', 'Color', [0 0.35 0.7], 'LineWidth', 1.5, 'DisplayName', 'calibrated Simulink model');
plot(ax, mid(use), yTrend(use, end), ':', 'Color', [0.85 0.4 0], 'LineWidth', 1.5, 'DisplayName', 'trend only');
yline(ax, 0, 'k-', 'HandleVisibility', 'off'); hold(ax, 'off'); grid(ax, 'on');
xlabel(ax, 'Chainage along the highway (km)'); ylabel(ax, 'Shoreline change 2009-2025 (m, + seaward)');
title(ax, 'Hindcast: model calibrated on 1986-2009, run 2009-2025, against the shoreline seen in 2025');
legend(ax, 'Location', 'best');
exportgraphics(fig, fullfile(cfg.figDir, 'shoreline_hindcast.png'), 'Resolution', 200);
fprintf('\nSaved results/shoreline_calibration.csv and results/figures/shoreline_hindcast.png\n');

% ===================================================================================================
function [t, y] = simChange(mdl, nSeg, r, D, a, Lm, waveYears, Pa, t1, t2)
in = Simulink.SimulationInput(mdl);
in = in.setModelParameter('StartTime', num2str(t1), 'StopTime', num2str(t2));
in = in.setVariable('nSeg', nSeg); in = in.setVariable('eprVec', r);
in = in.setVariable('extraRiseRate', [waveYears(:) zeros(numel(waveYears), 1)]);
in = in.setVariable('bruunFactor', 0);
in = in.setVariable('diffMatrix', D * Lm);
in = in.setVariable('waveAnom', [waveYears(:) Pa(:)]);
in = in.setVariable('waveGain', a * ones(nSeg, 1));
in = in.setVariable('y0vec', zeros(nSeg, 1));
out = sim(in);
t = out.tout; y = out.yOut;
end

function e = misfit(p, runModel, t1, t2, yrs, obs, use)
% mean squared difference between modelled and observed change, all km and epochs
[t, y] = runModel(p, t1, t2);
ym = interp1(t, y, yrs)';
d = ym(use, :) - obs(use, :);
e = mean(d(:).^2, 'omitnan');
end
