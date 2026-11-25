[out:json][timeout:240];
(
  way["building"](14.653,-17.455,14.690,-17.425);
  relation["building"](14.653,-17.455,14.690,-17.425);
  way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|pedestrian|primary_link|secondary_link|tertiary_link|trunk_link|road)$"](14.653,-17.455,14.690,-17.425);
  way["natural"="coastline"](14.640,-17.475,14.710,-17.405);
  node["place"~"^(suburb|neighbourhood|quarter)$"](14.648,-17.460,14.695,-17.420);
  nwr["name"]["amenity"~"^(place_of_worship|hospital|marketplace|police|townhall|university|bus_station|fuel|restaurant|cafe)$"](14.653,-17.455,14.690,-17.425);
  nwr["name"]["tourism"](14.653,-17.455,14.690,-17.425);
  nwr["name"]["place"="square"](14.653,-17.455,14.690,-17.425);
  nwr["name"]["leisure"="park"](14.653,-17.455,14.690,-17.425);
  nwr["name"]["railway"="station"](14.653,-17.455,14.690,-17.425);
  nwr["name"]["building"~"^(government|public|cathedral|mosque|train_station)$"](14.653,-17.455,14.690,-17.425);
);
out geom;