[out:json][timeout:120];
(
  way["railway"~"^(rail|light_rail)$"](14.653,-17.455,14.690,-17.425);
  way["landuse"~"^(industrial|port|railway|residential|commercial|retail)$"](14.653,-17.455,14.690,-17.425);
  nwr["amenity"="parking"](14.653,-17.455,14.690,-17.425);
);
out geom;
