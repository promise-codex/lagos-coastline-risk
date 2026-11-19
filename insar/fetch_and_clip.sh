#!/bin/bash
# fetch one HyP3 product, keep clipped rasters needed by MintPy
url="$1"; out=/home/user/insar/hyp3; name=$(basename "$url" .zip)
[ -f "$out/$name/$name.txt" ] && exit 0
tmp=$(mktemp -d /home/user/insar/tmp.XXXX)
for i in 1 2 3 4; do curl -sSf --max-time 600 -o "$tmp/p.zip" "$url" && break; sleep $((i*10)); done
[ -s "$tmp/p.zip" ] || { echo "FAIL $name" >> /home/user/insar/fail.log; rm -rf "$tmp"; exit 1; }
keep="unw_phase.tif corr.tif conncomp.tif"
[ -f $out/.static_done ] || keep="$keep dem.tif lv_theta.tif lv_phi.tif water_mask.tif"
pats=""; for k in $keep; do pats="$pats $name/${name}_$k"; done
unzip -qo "$tmp/p.zip" $pats "$name/$name.txt" -d "$tmp"
mkdir -p "$out/$name"
for k in $keep; do
  gdal_translate -q -projwin 538640 731760 660400 699840 -co COMPRESS=DEFLATE "$tmp/$name/${name}_$k" "$out/$name/${name}_$k"
done
cp "$tmp/$name/$name.txt" "$out/$name/"
[[ "$keep" == *dem* ]] && touch $out/.static_done
rm -rf "$tmp"
