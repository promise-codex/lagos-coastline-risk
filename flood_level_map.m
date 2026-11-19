function FL = flood_level_map(Z, M, levels, cfg)
%FLOOD_LEVEL_MAP Lowest water level at which each cell is flooded (bathtub, connected).
%   FL = flood_level_map(Z, M, levels, cfg) runs bathtub_flood at every
%   value in LEVELS (metres, ascending) and records, for each land cell,
%   the first level at which it floods. Cells that never flood within
%   LEVELS get Inf; water cells get NaN.
%
%   Because a connected bathtub only ever grows as the water rises, this
%   one map answers "is this cell flooded at water level h?" for any h:
%   flooded = FL <= h. That lets later steps turn a sea-level curve into a
%   year of first flooding without re-running the flood for every year.
%   The answer is exact to within one step of LEVELS.

levels = sort(levels(:))';
FL = inf(size(Z), 'single');
for k = 1:numel(levels)
    f = bathtub_flood(Z, M, levels(k), cfg);
    FL(f & isinf(FL)) = levels(k);
end
if isempty(M)
    FL(isnan(Z)) = NaN;
else
    FL(M ~= 0) = NaN;
end
end
