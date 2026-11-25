[out:json][timeout:180];
(
  node["highway"~"^(traffic_signals|stop|give_way|crossing)$"](14.653,-17.455,14.690,-17.425);
  nwr["leisure"~"^(pitch|park|sports_centre|stadium|playground)$"](14.653,-17.455,14.690,-17.425);
  nwr["natural"~"^(beach|sand)$"](14.645,-17.465,14.695,-17.420);
  nwr["amenity"="place_of_worship"](14.653,-17.455,14.690,-17.425);
  nwr["amenity"="marketplace"](14.653,-17.455,14.690,-17.425);
  nwr["landuse"~"^(grass|recreation_ground)$"](14.653,-17.455,14.690,-17.425);
);
out geom;