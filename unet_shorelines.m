%UNET_SHORELINES Step 7: a U-Net water map compared with the water index.
%   Step 6 (extract_shorelines) finds the shoreline where the water index
%   MNDWI crosses 0. This step trains a small U-Net (Deep Learning Toolbox
%   and Computer Vision Toolbox) to tell water from land on Sentinel-2, and
%   asks whether it puts the shoreline in a different place.
%
%   Data (data/shoreline/, made by shoreline/make_s2_band_composites.py and
%   shoreline/make_worldcover_labels.py):
%     sentinel2_bands_<year>.tif   yearly median reflectance x 10000, 20 m,
%                                  bands B02 B03 B04 B08 B11 B12, 2016-2025
%     worldcover_water_<year>.tif  ESA WorldCover 2020 and 2021, class 80
%                                  (permanent water) on the same grid;
%                                  255 = outside the coastal strip
%   WorldCover is made by ESA with its own classifier from Sentinel-1 and
%   Sentinel-2, so the U-Net does not learn our water index. WorldCover
%   has its own errors, so the pixel scores below are agreement with
%   WorldCover, not true accuracy.
%
%   Steps
%   1. Cut the 2021 image into 128 x 128 patches (stride 64). Every fourth
%      8 km block along the coast is held out for testing and never used
%      in training.
%   2. Train a U-Net (encoder depth 3, 16 first filters) with Adam,
%      cross-entropy loss, pixels outside the strip ignored, flips added.
%   3. Test on the held-out blocks in 2021 (new places) and 2020 (new
%      places and a new year, against WorldCover 2020), for the U-Net and
%      for MNDWI > 0 computed from the same image.
%   4. Map water probability for every year 2016-2025 and find the
%      shoreline on the same transects as step 6 (probability 0.5), and the
%      MNDWI shoreline from the same image (MNDWI 0).
%   5. Compare positions and 2016-2025 rates of the two methods.
%   Outputs: results/unet_water_net.mat, results/unet_vs_mndwi.csv,
%   results/figures/unet_vs_mndwi.png. Training takes about 5 to 15
%   minutes on the MATLAB Online CPU.

cfg = project_config();
shoreDir = fullfile(cfg.dataDir, 'shoreline');
rng(1);
psz = 128; stride = 64;
blockKm = 8; testEvery = 4;                 % every 4th 8 km block is test

% ---- 1. Training and test patches (2021) -------------------------------------------
[X21, R] = readBands(shoreDir, 2021);
L21 = readgeoraster(fullfile(shoreDir, 'worldcover_water_2021.tif'));
[r0, c0] = patchOrigins(size(L21), psz, stride);
xc = R.XWorldLimits(1) + (c0 + psz / 2) * R.CellExtentInWorldX;          % patch centre easting
isTest = mod(floor((xc - R.XWorldLimits(1)) / (blockKm * 1000)), testEvery) == testEvery - 1;
validShare = arrayfun(@(i) mean(L21(r0(i):r0(i) + psz - 1, c0(i):c0(i) + psz - 1) ~= 255, 'all'), 1:numel(r0))';
keep = validShare >= 0.3;
[Xtr, Ttr] = makePatches(X21, L21, r0(keep & ~isTest), c0(keep & ~isTest), psz);
[Xva, Tva] = makePatches(X21, L21, r0(keep & isTest), c0(keep & isTest), psz);
% flips (left-right, up-down, both) to show the network more coast shapes
Xtr = cat(4, Xtr, flip(Xtr, 2), flip(Xtr, 1), flip(flip(Xtr, 1), 2));
Ttr = cat(4, Ttr, flip(Ttr, 2), flip(Ttr, 1), flip(flip(Ttr, 1), 2));
fprintf('Patches: %d for training (with flips), %d held out for testing.\n', size(Xtr, 4), size(Xva, 4));

% ---- 2. Train ----------------------------------------------------------------------
netFile = fullfile(cfg.resultsDir, 'unet_water_net.mat');
if isfile(netFile)
    load(netFile, 'net'); fprintf('Loaded the trained network from %s (delete it to train again).\n', netFile);
else
    net = unet([psz psz 6], 2, EncoderDepth = 3, NumFirstEncoderFilters = 16);
    opts = trainingOptions('adam', MaxEpochs = 30, MiniBatchSize = 16, InitialLearnRate = 1e-3, ...
        Shuffle = 'every-epoch', ValidationData = {Xva, Tva}, ValidationFrequency = 50, ...
        Verbose = true, VerboseFrequency = 50, Plots = 'none');
    % Pixels outside the strip have both target channels 0, so they add
    % nothing to the cross-entropy loss.
    tic; net = trainnet(Xtr, Ttr, net, 'crossentropy', opts);
    fprintf('Training took %.1f minutes.\n', toc / 60);
    save(netFile, 'net');
end

% ---- 3. Pixel test on held-out blocks ---------------------------------------------------
testMask = false(size(L21));
for i = find(keep & isTest)'
    testMask(r0(i):r0(i) + psz - 1, c0(i):c0(i) + psz - 1) = true;
end
fprintf('\nPixel test on held-out blocks, agreement with ESA WorldCover water:\n');
fprintf('  %-34s %8s %8s %8s\n', 'case', 'IoU', 'accuracy', 'pixels');
for yy = [2021 2020]
    if yy == 2021, X = X21; else, X = readBands(shoreDir, yy); end
    Lw = readgeoraster(fullfile(shoreDir, sprintf('worldcover_water_%d.tif', yy)));
    pw = predictWater(net, X, psz, stride);
    m = mndwiOf(X);
    ok = testMask & Lw ~= 255 & ~isnan(m);
    truth = Lw(ok) == 1;
    [iou, acc] = scores(pw(ok) >= 0.5, truth);
    fprintf('  %-34s %8.3f %8.3f %8d\n', sprintf('U-Net, %d image vs WorldCover %d', yy, yy), iou, acc, sum(ok(:)));
    [iou, acc] = scores(m(ok) >= cfg.mndwiThreshold, truth);
    fprintf('  %-34s %8.3f %8.3f %8d\n', sprintf('MNDWI > 0, %d', yy), iou, acc, sum(ok(:)));
end

% ---- 4. Shorelines from both methods on the same images -------------------------------
H = load(fullfile(cfg.osmDir, 'highway_segments.mat'), 'segs', 'samples');
segs = H.segs; nSeg = height(segs); mid = (segs.start_km + segs.end_km) / 2;
[x0, y0, nrm, s] = shore_transects(cfg, H.samples, mid);
years = 2016:2025;
Pu = nan(nSeg, numel(years)); Pm = Pu;
for j = 1:numel(years)
    X = readBands(shoreDir, years(j));
    pw = predictWater(net, X, psz, stride); m = mndwiOf(X);
    for k = 1:nSeg
        if isnan(x0(k)), continue, end
        [ci, ri] = worldToIntrinsic(R, x0(k) + s * nrm(k, 1), y0(k) + s * nrm(k, 2));
        many = 99 * ones(size(s));                         % clear-look count is not used here
        Pu(k, j) = shore_position(s, interp2(pw, ci, ri, 'linear'), many, 0.5, 1);
        Pm(k, j) = shore_position(s, interp2(m, ci, ri, 'linear'), many, cfg.mndwiThreshold, 1);
    end
    fprintf('  %d: shoreline found at %d km (U-Net) and %d km (MNDWI)\n', years(j), sum(~isnan(Pu(:, j))), sum(~isnan(Pm(:, j))));
end

% ---- 5. Compare ----------------------------------------------------------------------------
d = Pu - Pm; dv = d(~isnan(d));
fprintf('\nShoreline position, U-Net minus MNDWI, same image, %d km-years (positive = U-Net further out to sea):\n', numel(dv));
fprintf('  median %.1f m, robust spread (1.48 x MAD) %.1f m, share within 20 m (one pixel): %.0f%%\n', ...
    median(dv), 1.4826 * median(abs(dv - median(dv))), 100 * mean(abs(dv) <= 20));
ru = nan(nSeg, 1); rm = ru;
for k = 1:nSeg
    v = ~isnan(Pu(k, :)) & ~isnan(Pm(k, :));
    if sum(v) < 6, continue, end
    b = robustfit(years(v)', Pu(k, v)'); ru(k) = b(2);
    b = robustfit(years(v)', Pm(k, v)'); rm(k) = b(2);
end
c = ~isnan(ru) & abs(ru) < 50 & abs(rm) < 50;              % leave out the reclamation jumps
fprintf('Rate 2016-2025 (robust fit), %d km: U-Net minus MNDWI median %.2f m/yr, robust spread %.2f, r = %.2f\n', ...
    sum(c), median(ru(c) - rm(c)), 1.4826 * median(abs(ru(c) - rm(c) - median(ru(c) - rm(c)))), corr(ru(c), rm(c)));

T = segs(:, {'segment', 'start_km', 'end_km'});
T.median_offset_unet_minus_mndwi_m = median(d, 2, 'omitnan');
T.rate_2016_2025_unet_m_yr = ru; T.rate_2016_2025_mndwi_m_yr = rm;
writetable(T, fullfile(cfg.resultsDir, 'unet_vs_mndwi.csv'));

fig = figure('Color', 'w', 'Position', [80 80 1150 640]);
tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact');
ax = nexttile(tl, [1 2]);
% a 10 km stretch of the 2021 water probability with both shorelines
[~, k1] = min(abs(mid - 30)); x1 = x0(k1) - 5000; x2 = x0(k1) + 5000;
[cA, ~] = worldToIntrinsic(R, [x1 x2], [y0(k1) y0(k1)]);
cols = max(1, round(cA(1))):min(size(L21, 2), round(cA(2)));
pw21 = predictWater(net, X21, psz, stride);
imagesc(ax, R.XWorldLimits(1) + (cols - 0.5) * R.CellExtentInWorldX - x1, ...
    R.YWorldLimits(2) - ((1:size(L21, 1)) - 0.5) * R.CellExtentInWorldY, pw21(:, cols));
axis(ax, 'xy'); axis(ax, 'equal'); colormap(ax, parula); cb = colorbar(ax); cb.Label.String = 'U-Net water probability';
hold(ax, 'on');
contour(ax, R.XWorldLimits(1) + (cols - 0.5) * R.CellExtentInWorldX - x1, ...
    R.YWorldLimits(2) - ((1:size(L21, 1)) - 0.5) * R.CellExtentInWorldY, mndwiOf(X21(:, cols, :)), [0 0], 'r', 'LineWidth', 1);
hold(ax, 'off');
ylim(ax, y0(k1) + [-4000 1000]); xlabel(ax, 'Easting from start of stretch (m)'); ylabel(ax, 'Northing (m)');
title(ax, 'Sentinel-2 2021 near km 30: U-Net water probability (colour) and MNDWI = 0 line (red)');
ax = nexttile(tl);
histogram(ax, dv(abs(dv) <= 100), -100:5:100);
xlabel(ax, 'U-Net minus MNDWI shoreline (m)'); ylabel(ax, 'km-years'); grid(ax, 'on');
title(ax, sprintf('Position difference (median %.1f m)', median(dv)));
ax = nexttile(tl);
plot(ax, rm(c), ru(c), 'o', 'MarkerFaceColor', [0 0.35 0.7]); hold(ax, 'on');
lim = [min([rm(c); ru(c)]) max([rm(c); ru(c)])]; plot(ax, lim, lim, 'k--'); hold(ax, 'off');
grid(ax, 'on'); axis(ax, 'equal');
xlabel(ax, 'MNDWI rate 2016-2025 (m/yr)'); ylabel(ax, 'U-Net rate 2016-2025 (m/yr)');
title(ax, sprintf('Shoreline change rate per km (r = %.2f)', corr(ru(c), rm(c))));
exportgraphics(fig, fullfile(cfg.figDir, 'unet_vs_mndwi.png'), 'Resolution', 200);
fprintf('\nSaved results/unet_vs_mndwi.csv, results/unet_water_net.mat and results/figures/unet_vs_mndwi.png.\n');

% =========================================================================================
function [X, R] = readBands(dirName, yr)
[A, R] = readgeoraster(fullfile(dirName, sprintf('sentinel2_bands_%d.tif', yr)));
X = single(A) / 10000;                     % reflectance; 0 = no data
end

function m = mndwiOf(X)
g = X(:, :, 2); sw = X(:, :, 5);
m = (g - sw) ./ (g + sw); m(g == 0 | sw == 0) = NaN;
end

function [r0, c0] = patchOrigins(sz, psz, stride)
[c0, r0] = meshgrid(1:stride:sz(2) - psz + 1, 1:stride:sz(1) - psz + 1);
r0 = r0(:); c0 = c0(:);
end

function [Xp, Tp] = makePatches(X, L, r0, c0, psz)
n = numel(r0);
Xp = zeros(psz, psz, 6, n, 'single'); Tp = zeros(psz, psz, 2, n, 'single');
for i = 1:n
    rr = r0(i):r0(i) + psz - 1; cc = c0(i):c0(i) + psz - 1;
    Xp(:, :, :, i) = X(rr, cc, :);
    l = L(rr, cc);
    Tp(:, :, 1, i) = l == 0;                % land
    Tp(:, :, 2, i) = l == 1;                % water (255 = ignored: both 0)
end
end

function pw = predictWater(net, X, psz, stride)
% Tiles of psz with step stride; only the centre stride x stride part of
% each tile is kept, so every pixel is predicted away from a tile edge.
mg = (psz - stride) / 2;
[h, w, ~] = size(X);
H2 = ceil(h / stride) * stride + 2 * mg; W2 = ceil(w / stride) * stride + 2 * mg;
Xp = zeros(H2, W2, size(X, 3), 'single'); Xp(mg + (1:h), mg + (1:w), :) = X;
[c0, r0] = meshgrid(1:stride:W2 - psz + 1, 1:stride:H2 - psz + 1);
r0 = r0(:); c0 = c0(:);
tiles = zeros(psz, psz, size(X, 3), numel(r0), 'single');
for i = 1:numel(r0), tiles(:, :, :, i) = Xp(r0(i):r0(i) + psz - 1, c0(i):c0(i) + psz - 1, :); end
Y = minibatchpredict(net, tiles, MiniBatchSize = 32);
P = zeros(H2, W2, 'single');
for i = 1:numel(r0)
    P(r0(i) + mg + (0:stride - 1), c0(i) + mg + (0:stride - 1)) = Y(mg + (1:stride), mg + (1:stride), 2, i);
end
pw = P(mg + (1:h), mg + (1:w));
pw(all(X == 0, 3)) = NaN;                  % outside the strip
end

function [iou, acc] = scores(pred, truth)
iou = sum(pred & truth) / sum(pred | truth);
acc = mean(pred == truth);
end
