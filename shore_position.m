function p = shore_position(s, prof, obs, th, minObs)
%SHORE_POSITION Shoreline position on one transect profile.
%   p = shore_position(s, prof, obs, th, minObs): s = distance along the
%   transect (m), prof = water score sampled on it (MNDWI, or U-Net water
%   probability), obs = clear looks at each sample, th = water threshold,
%   minObs = clear looks needed at the shoreline. Walking in from the sea
%   end (last sample with data, which must be water), the shoreline is the
%   first place where prof falls below th, found by linear interpolation
%   between the two samples either side. NaN if the sea end is not water,
%   if a data gap comes before land, or if there are too few clear looks.
p = NaN;
e = find(~isnan(prof), 1, 'last');                          % sea end = last sample with data
if isempty(e) || prof(e) < th, return, end                  % it must be water
prof = prof(1:e); obs = obs(1:e); s = s(1:e);
i = find(isnan(prof) | prof < th, 1, 'last');               % last land or gap sample, seen from the road side
if isempty(i), return, end
if isnan(prof(i)), return, end                              % gap before reaching land: no position
if obs(i) < minObs || obs(i + 1) < minObs, return, end
p = s(i) + (th - prof(i)) / (prof(i + 1) - prof(i)) * (s(i + 1) - s(i));
end
