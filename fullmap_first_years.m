function [yrAny, yrOcean] = fullmap_first_years(Z, M, V, years, h, t0, Ecols, cfg, road)
%FULLMAP_FIRST_YEARS First year each road km is reached, with land sinking pixel by pixel.
%   For each year t in YEARS the elevation model is moved by the land
%   motion map V (m/yr, positive = up):
%       Z(t) = Z + V * (t - t0)
%   and the connected bathtub is run twice:
%     any water   all water classes (sea, lagoon, creeks) at the mean level h(t)
%     ocean only  the open sea at h(t) + E, for each extra event level E
%                 (tide or storm), one row of Ecols per event, one value
%                 per grid column (so it can vary along the coast)
%   A cell that has been reached stays reached in later years. A segment
%   is reached when cfg.segmentWetShare of its land points are wet.
%
%   yrAny    nSeg x 1, first year reached by any water at mean level
%   yrOcean  nSeg x nEvents, first year reached from the open sea
%   Inf = not reached in YEARS, NaN = no land points in that segment.
%   Rows of Ecols that are all zero are skipped (yrOcean = Inf there,
%   because the any-water run already covers the mean level).

cfgO = cfg; cfgO.waterSeedClasses = 1;
nEv = size(Ecols, 1);
wetAny = false(size(Z)); wetOc = false([size(Z) nEv]);
yrAny = inf(road.nSeg, 1); yrOcean = inf(road.nSeg, nEv);
doEv = any(Ecols ~= 0, 2);
for k = 1:numel(years)
    Zt = Z + V * (years(k) - t0);
    wetAny = wetAny | bathtub_flood(Zt, M, h(k), cfg);
    yrAny = firstReached(yrAny, wetAny, road, cfg, years(k));
    for e = find(doEv)'
        w = wetOc(:, :, e) | bathtub_flood(Zt, M, h(k) + Ecols(e, :), cfgO);
        wetOc(:, :, e) = w;
        yrOcean(:, e) = firstReached(yrOcean(:, e), w, road, cfg, years(k));
    end
end
none = road.nLand == 0;
yrAny(none) = NaN; yrOcean(none, :) = NaN;
end

function yr = firstReached(yr, wet, road, cfg, t)
share = accumarray(road.seg, double(wet(road.idx)), [road.nSeg 1]) ./ max(road.nLand, 1);
yr(share >= cfg.segmentWetShare & isinf(yr) & road.nLand > 0) = t;
end
