function flooded = bathtub_flood(Z, M, waterLevel, cfg)
%BATHTUB_FLOOD Method M0: connected bathtub flooding.
%   flooded = bathtub_flood(Z, M, waterLevel, cfg) returns a logical grid
%   that is true for LAND cells that end up under water when the sea
%   stands at waterLevel metres (same datum as Z).
%
%   A land cell floods only if (1) its elevation is at or below waterLevel
%   and (2) it is connected to the sea through other such cells. Rule (2)
%   stops low inland hollows from being counted when no water can reach
%   them. This is the standard "connected bathtub" method.
%
%   Water that already exists (the seed) comes from the DeltaDTM mask
%   classes listed in cfg.waterSeedClasses. If M is empty, the no-data
%   cells of Z are used as water instead.

if isempty(M)
    water = isnan(Z);
    land  = ~water;
else
    water = ismember(M, cfg.waterSeedClasses);
    land  = (M == 0);          % 255 (above +10 m) is never flooded here
end

% Cells water may occupy: existing water plus low land
canFlood = water | (land & ~isnan(Z) & Z <= waterLevel);

% Keep only the low land connected to existing water
reached = imreconstruct(water, canFlood, cfg.connectivity);

flooded = reached & land;
end
