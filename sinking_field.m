function [V, S, src] = sinking_field(cfg, R, sz, farFill)
%SINKING_FIELD Radar land-motion rate on the elevation-model grid.
%   [V, S, src] = sinking_field(cfg, R, sz, farFill) returns, for every cell of the
%   elevation grid (reference R, size sz):
%     V    vertical rate in m/yr, positive = up (so sinking is negative)
%     S    local 1-sigma of that rate in m/yr (GPS tie error not included)
%     src  1 = radar pixel at this spot, 2 = mean of radar pixels within
%          cfg.insarBuffer_m, 3 = mean within 3 x cfg.insarBuffer_m,
%          4 = further than 3 x cfg.insarBuffer_m from any radar pixel,
%          filled by the option farFill (default cfg.insarFarFill, see below)
%   Gaps (water, dense vegetation, low coherence) are filled on the 80 m
%   radar grid first, with the average of the good radar
%   pixels around them (normalised convolution), then the filled grid is sampled at each elevation
%   cell (nearest radar cell). Filled cells get a larger sigma: the local
%   sigma plus the spread of the pixels used to fill them.

[A, Rg] = readgeoraster(cfg.insarFile);
v = double(A(:, :, 1)); s = double(A(:, :, 2));
good = ~isnan(v) & ~isnan(s);
v(~good) = 0; s(~good) = 0;

% pixel size in metres (about 80 m)
pxM = 1000 * 111.32 * cosd(mean(cfg.latlim)) * Rg.CellExtentInLongitude;

vf = nan(size(v)); sf = nan(size(v)); code = zeros(size(v), 'uint8');
vf(good) = v(good); sf(good) = s(good); code(good) = 1;
radii = cfg.insarBuffer_m * [1 3];
for j = 1:2
    r = max(1, round(radii(j) / pxM));
    [x, y] = meshgrid(-r:r); K = double(x.^2 + y.^2 <= r^2);
    n  = conv2(double(good), K, 'same');
    m1 = conv2(v .* good, K, 'same') ./ n;               % mean of good pixels in the disc
    m2 = conv2(v.^2 .* good, K, 'same') ./ n;
    sp = sqrt(max(m2 - m1.^2, 0));                      % their spread
    ms = conv2(s .* good, K, 'same') ./ n;
    use = isnan(vf) & n >= cfg.insarMinPixels;
    vf(use) = m1(use); sf(use) = sqrt(ms(use).^2 + sp(use).^2); code(use) = 1 + j;
end
% Cells still empty are more than 1.5 km from any good radar pixel (mostly
% wetland and bush). How to fill them is a choice, so three options exist
% and run_fullmap_sinking compares them:
%   'regional'  Gaussian-weighted average of radar pixels around the cell
%               (sigma cfg.insarRegional_m), then the scene median where
%               even that has too few pixels. Smooth; the default.
%   'median'    median of all radar pixels (no local information)
%   'nearest'   the single nearest radar pixel (gives sharp wedges)
if nargin < 4, farFill = cfg.insarFarFill; end
rest = isnan(vf);
allSpread = std(v(good)); allMed = median(v(good));
if any(rest(:))
    switch farFill
        case 'regional'
            sg = cfg.insarRegional_m / pxM; r = ceil(3 * sg);
            g = exp(-(-r:r)'.^2 / (2 * sg^2));            % separable Gaussian, peak 1
            n  = conv2(g, g, double(good), 'same');       % effective number of pixels
            m1 = conv2(g, g, v .* good, 'same') ./ n;
            m2 = conv2(g, g, v.^2 .* good, 'same') ./ n;
            ms = conv2(g, g, s .* good, 'same') ./ n;
            sp = sqrt(max(m2 - m1.^2, 0));
            use = rest & n >= cfg.insarMinPixels;
            vf(use) = m1(use); sf(use) = sqrt(ms(use).^2 + sp(use).^2);
            rest2 = rest & ~use;
            vf(rest2) = allMed; sf(rest2) = allSpread;
        case 'median'
            vf(rest) = allMed; sf(rest) = allSpread;
        case 'nearest'
            [~, nearestIdx] = bwdist(good);
            vf(rest) = v(nearestIdx(rest));
            sf(rest) = sqrt(s(nearestIdx(rest)).^2 + allSpread^2);
        otherwise
            error('sinking_field:fill', 'Unknown fill option %s', farFill);
    end
    code(rest) = 4;
end

% sample at every elevation cell
[lat, lon] = geographicGrid(R);
[I, J] = geographicToDiscrete(Rg, lat(:), lon(:));
out = isnan(I) | isnan(J);                              % outside the radar footprint
I(out) = 1; J(out) = 1;
k = sub2ind(size(vf), I, J);
V = reshape(vf(k), sz) / 1000; S = reshape(sf(k), sz) / 1000; src = reshape(code(k), sz);
if any(out)
    % outside the footprint: nearest edge value is not measured, so use the
    % median of all radar pixels and flag it
    V(out) = allMed / 1000; S(out) = allSpread / 1000; src(out) = 4;
end
V = single(V); S = single(S);
end
