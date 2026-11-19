function road = road_cells(cfg, R, M)
%ROAD_CELLS Elevation-grid cells under the mapped highway, grouped by 1 km segment.
%   road.idx    linear index of each road sample point that lies on land
%   road.seg    its segment number
%   road.nSeg   number of segments
%   road.nLand  land points per segment (0 = segment entirely over water or unmapped)
%   Points over water cells (bridges) are left out, as in run_m1_sinking.
H = load(fullfile(cfg.osmDir, 'highway_segments.mat'), 'segs', 'samples');
[I, J] = geographicToDiscrete(R, H.samples.lat, H.samples.lon);
segOf = discretize(H.samples.chainage_km(:), [H.segs.start_km; H.segs.end_km(end)]);
use = ~isnan(I(:)) & ~isnan(J(:)) & H.samples.mapped(:) & ~isnan(segOf);
idx = sub2ind(size(M), I(use), J(use));
onLand = M(idx) == 0;
road.idx = idx(onLand);
road.seg = segOf(use);
road.seg = road.seg(onLand);
road.nSeg = height(H.segs);
road.nLand = accumarray(road.seg, 1, [road.nSeg 1]);
road.segs = H.segs;
end
