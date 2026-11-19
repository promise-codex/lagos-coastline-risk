function [x0, y0, nrm, s] = shore_transects(cfg, samples, mid)
%SHORE_TRANSECTS One transect per road km, from the road at right angles out to sea.
%   [x0, y0, nrm, s] = shore_transects(cfg, samples, mid) returns, for road
%   km centres mid (chainage, km), the start point (x0, y0, UTM 31N metres),
%   the unit normal pointing south to the sea (nrm, one row per km) and the
%   sample distances along the transect from the road (s, every 5 m, from
%   300 m inland to cfg.transectLength_m out to sea).
%   Used by extract_shorelines and unet_shorelines so both methods read the
%   same lines.
utm = projcrs(32631);
ok = samples.mapped(:) & ~isnan(samples.lat(:));
[sx, sy] = projfwd(utm, samples.lat(ok), samples.lon(ok));
sc = samples.chainage_km(ok);
x0 = interp1(sc, sx, mid); y0 = interp1(sc, sy, mid);
xa = interp1(sc, sx, mid - 0.5, 'linear', 'extrap'); ya = interp1(sc, sy, mid - 0.5, 'linear', 'extrap');
xb = interp1(sc, sx, mid + 0.5, 'linear', 'extrap'); yb = interp1(sc, sy, mid + 0.5, 'linear', 'extrap');
t = [xb - xa, yb - ya]; t = t ./ vecnorm(t, 2, 2);
nrm = [t(:, 2), -t(:, 1)];                                 % one of the two normals
flip = nrm(:, 2) > 0; nrm(flip, :) = -nrm(flip, :);       % make it point south, to the sea
s = (-300:5:cfg.transectLength_m)';                        % distance along the transect from the road (m)
end
