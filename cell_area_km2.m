function A = cell_area_km2(R)
%CELL_AREA_KM2 Area of each grid cell in square kilometres.
%   A = cell_area_km2(R) returns a matrix the size of the raster. Cells
%   shrink in the east-west direction as latitude rises, so the area is
%   computed per row on a sphere of radius 6371 km.

[lat, ~] = geographicGrid(R);
if strcmp(R.RasterInterpretation, 'postings')
    dlat = R.SampleSpacingInLatitude;
    dlon = R.SampleSpacingInLongitude;
else
    dlat = R.CellExtentInLatitude;
    dlon = R.CellExtentInLongitude;
end
kmPerDeg = pi/180 * 6371;
A = (kmPerDeg * dlat) .* (kmPerDeg * dlon .* cosd(lat));
end
