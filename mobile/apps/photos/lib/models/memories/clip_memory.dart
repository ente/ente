import "package:photos/generated/l10n.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";

enum ClipMemoryType {
  sunrise,
  mountains,
  greenery,
  beach,
  city,
  moon,
  onTheRoad,
  food,
  pets,
  festivities,
  snowAdventures,
  waterfalls,
  wildlife,
  flowers,
  nightLights,
  architecture,
  autumnColors,
  desertDreams,
  stargazing,
  lakeside,
  rainyDays,
  sportsAction,
  streetArt,
  familyMoments,
  fireworks,
  historicSites,
  tropicalParadise,
  forestTrails,
  citySunsets,
  colorfulMarkets,
  cozyCafes,
  vintageVibes,
  aerialViews,
  artisticPortraits,
  streetFood,
  riverCruises,
  playfulKids,
  coastalCliffs,
  candidLaughter,
  groupSelfies,
  birthdayJoy,
  weddingMoments,
  goldenHourPortraits,
  concertNights,
  poolDays,
  picnicDays,
  campingMoments,
  babySmiles,
}

ClipMemoryType clipMemoryTypeFromString(String type) {
  switch (type) {
    case "sunrise":
      return ClipMemoryType.sunrise;
    case "mountains":
      return ClipMemoryType.mountains;
    case "greenery":
      return ClipMemoryType.greenery;
    case "beach":
      return ClipMemoryType.beach;
    case "city":
      return ClipMemoryType.city;
    case "moon":
      return ClipMemoryType.moon;
    case "onTheRoad":
      return ClipMemoryType.onTheRoad;
    case "food":
      return ClipMemoryType.food;
    case "pets":
      return ClipMemoryType.pets;
    case "festivities":
      return ClipMemoryType.festivities;
    case "snowAdventures":
      return ClipMemoryType.snowAdventures;
    case "waterfalls":
      return ClipMemoryType.waterfalls;
    case "wildlife":
      return ClipMemoryType.wildlife;
    case "flowers":
      return ClipMemoryType.flowers;
    case "nightLights":
      return ClipMemoryType.nightLights;
    case "architecture":
      return ClipMemoryType.architecture;
    case "autumnColors":
      return ClipMemoryType.autumnColors;
    case "desertDreams":
      return ClipMemoryType.desertDreams;
    case "stargazing":
      return ClipMemoryType.stargazing;
    case "lakeside":
      return ClipMemoryType.lakeside;
    case "rainyDays":
      return ClipMemoryType.rainyDays;
    case "sportsAction":
      return ClipMemoryType.sportsAction;
    case "streetArt":
      return ClipMemoryType.streetArt;
    case "familyMoments":
      return ClipMemoryType.familyMoments;
    case "fireworks":
      return ClipMemoryType.fireworks;
    case "historicSites":
      return ClipMemoryType.historicSites;
    case "tropicalParadise":
      return ClipMemoryType.tropicalParadise;
    case "forestTrails":
      return ClipMemoryType.forestTrails;
    case "citySunsets":
      return ClipMemoryType.citySunsets;
    case "colorfulMarkets":
      return ClipMemoryType.colorfulMarkets;
    case "cozyCafes":
      return ClipMemoryType.cozyCafes;
    case "vintageVibes":
      return ClipMemoryType.vintageVibes;
    case "aerialViews":
      return ClipMemoryType.aerialViews;
    case "artisticPortraits":
      return ClipMemoryType.artisticPortraits;
    case "streetFood":
      return ClipMemoryType.streetFood;
    case "riverCruises":
      return ClipMemoryType.riverCruises;
    case "playfulKids":
      return ClipMemoryType.playfulKids;
    case "coastalCliffs":
      return ClipMemoryType.coastalCliffs;
    case "candidLaughter":
      return ClipMemoryType.candidLaughter;
    case "groupSelfies":
      return ClipMemoryType.groupSelfies;
    case "birthdayJoy":
      return ClipMemoryType.birthdayJoy;
    case "weddingMoments":
      return ClipMemoryType.weddingMoments;
    case "goldenHourPortraits":
      return ClipMemoryType.goldenHourPortraits;
    case "concertNights":
      return ClipMemoryType.concertNights;
    case "poolDays":
      return ClipMemoryType.poolDays;
    case "picnicDays":
      return ClipMemoryType.picnicDays;
    case "campingMoments":
      return ClipMemoryType.campingMoments;
    case "babySmiles":
      return ClipMemoryType.babySmiles;
    default:
      throw ArgumentError("Invalid people memory type: $type");
  }
}

String clipQuery(ClipMemoryType clipMemoryType) {
  switch (clipMemoryType) {
    case ClipMemoryType.sunrise:
      return "Photo of an absolutely stunning sunrise or sunset";
    case ClipMemoryType.mountains:
      return "Photo of a beautiful mountain range";
    case ClipMemoryType.greenery:
      return "Photo of lush greenery";
    case ClipMemoryType.beach:
      return "Photo of a beautiful beach";
    case ClipMemoryType.city:
      return "Beautiful photo showing a metropolitan city";
    case ClipMemoryType.moon:
      return "Photo of a beautiful moon";
    case ClipMemoryType.onTheRoad:
      return "Photo of a nostalgic road trip";
    case ClipMemoryType.food:
      return "Photo of delicious looking food";
    case ClipMemoryType.pets:
      return "Photo of cute pets";
    case ClipMemoryType.festivities:
      return "Photo capturing a joyful celebration or festival";
    case ClipMemoryType.snowAdventures:
      return "Photo of a cozy winter adventure in the snow";
    case ClipMemoryType.waterfalls:
      return "Photo of a majestic waterfall cascading through nature";
    case ClipMemoryType.wildlife:
      return "Photo of a magnificent wild animal in its natural habitat";
    case ClipMemoryType.flowers:
      return "Photo of vibrant blooming flowers in a garden";
    case ClipMemoryType.nightLights:
      return "Photo of dazzling city lights glowing at night";
    case ClipMemoryType.architecture:
      return "Photo showcasing striking architectural design or landmark";
    case ClipMemoryType.autumnColors:
      return "Photo of trees glowing with vibrant autumn colors";
    case ClipMemoryType.desertDreams:
      return "Photo of sweeping desert dunes under golden light";
    case ClipMemoryType.stargazing:
      return "Photo of a brilliant night sky filled with stars or the Milky Way";
    case ClipMemoryType.lakeside:
      return "Photo of a serene lake reflecting the surrounding landscape";
    case ClipMemoryType.rainyDays:
      return "Photo capturing the cozy mood of a rainy day";
    case ClipMemoryType.sportsAction:
      return "Photo of thrilling sports action frozen in motion";
    case ClipMemoryType.streetArt:
      return "Photo showcasing vibrant street art or graffiti murals";
    case ClipMemoryType.familyMoments:
      return "Photo capturing heartwarming moments with family";
    case ClipMemoryType.fireworks:
      return "Photo of dazzling fireworks bursting in the sky";
    case ClipMemoryType.historicSites:
      return "Photo of an awe-inspiring historical monument or landmark";
    case ClipMemoryType.tropicalParadise:
      return "Photo of a dreamy tropical paradise with turquoise water and palm trees";
    case ClipMemoryType.forestTrails:
      return "Photo of a peaceful forest trail bathed in soft light";
    case ClipMemoryType.citySunsets:
      return "Photo of a vibrant sunset casting colors over a city skyline";
    case ClipMemoryType.colorfulMarkets:
      return "Photo of a bustling market overflowing with colorful stalls";
    case ClipMemoryType.cozyCafes:
      return "Photo of a cozy cafe scene with warm ambience";
    case ClipMemoryType.vintageVibes:
      return "Photo with a charming vintage aesthetic or retro details";
    case ClipMemoryType.aerialViews:
      return "Photo captured from above showing sweeping aerial views";
    case ClipMemoryType.artisticPortraits:
      return "Photo of an expressive artistic portrait";
    case ClipMemoryType.streetFood:
      return "Photo of mouthwatering street food being prepared or served";
    case ClipMemoryType.riverCruises:
      return "Photo of a scenic river cruise or boat drifting along the water";
    case ClipMemoryType.playfulKids:
      return "Photo capturing joyful kids playing and laughing";
    case ClipMemoryType.coastalCliffs:
      return "Photo of dramatic coastal cliffs meeting the sea";
    case ClipMemoryType.candidLaughter:
      return "Photo capturing candid laughter, joy, and shared smiles";
    case ClipMemoryType.groupSelfies:
      return "Photo of friends or family gathered for a fun group selfie";
    case ClipMemoryType.birthdayJoy:
      return "Photo of a birthday celebration with cake, candles, and happy faces";
    case ClipMemoryType.weddingMoments:
      return "Photo capturing a wedding moment full of love, celebration, and togetherness";
    case ClipMemoryType.goldenHourPortraits:
      return "Photo of a beautiful portrait taken in warm golden hour light";
    case ClipMemoryType.concertNights:
      return "Photo of a live concert, music performance, or crowd under stage lights";
    case ClipMemoryType.poolDays:
      return "Photo of a fun summer day at the pool with splashes and sunshine";
    case ClipMemoryType.picnicDays:
      return "Photo of a relaxed picnic outdoors with food, blankets, and loved ones";
    case ClipMemoryType.campingMoments:
      return "Photo of a camping trip with tents, campfires, or cozy outdoor moments";
    case ClipMemoryType.babySmiles:
      return "Photo capturing a baby smiling, laughing, or sharing a tender family moment";
  }
}

String clipTitle(AppLocalizations locals, ClipMemoryType clipMemoryType) {
  switch (clipMemoryType) {
    case ClipMemoryType.sunrise:
      return locals.sunrise;
    case ClipMemoryType.mountains:
      return locals.mountains;
    case ClipMemoryType.greenery:
      return locals.greenery;
    case ClipMemoryType.beach:
      return locals.beach;
    case ClipMemoryType.city:
      return locals.city;
    case ClipMemoryType.moon:
      return locals.moon;
    case ClipMemoryType.onTheRoad:
      return locals.onTheRoad;
    case ClipMemoryType.food:
      return locals.food;
    case ClipMemoryType.pets:
      return locals.pets;
    case ClipMemoryType.festivities:
      return locals.festivities;
    case ClipMemoryType.snowAdventures:
      return locals.snowAdventures;
    case ClipMemoryType.waterfalls:
      return locals.waterfalls;
    case ClipMemoryType.wildlife:
      return locals.wildlife;
    case ClipMemoryType.flowers:
      return locals.flowers;
    case ClipMemoryType.nightLights:
      return locals.nightLights;
    case ClipMemoryType.architecture:
      return locals.architecture;
    case ClipMemoryType.autumnColors:
      return locals.autumnColors;
    case ClipMemoryType.desertDreams:
      return locals.desertDreams;
    case ClipMemoryType.stargazing:
      return locals.stargazing;
    case ClipMemoryType.lakeside:
      return locals.lakeside;
    case ClipMemoryType.rainyDays:
      return locals.rainyDays;
    case ClipMemoryType.sportsAction:
      return locals.sportsAction;
    case ClipMemoryType.streetArt:
      return locals.streetArt;
    case ClipMemoryType.familyMoments:
      return locals.familyMoments;
    case ClipMemoryType.fireworks:
      return locals.fireworks;
    case ClipMemoryType.historicSites:
      return locals.historicSites;
    case ClipMemoryType.tropicalParadise:
      return locals.tropicalParadise;
    case ClipMemoryType.forestTrails:
      return locals.forestTrails;
    case ClipMemoryType.citySunsets:
      return locals.citySunsets;
    case ClipMemoryType.colorfulMarkets:
      return locals.colorfulMarkets;
    case ClipMemoryType.cozyCafes:
      return locals.cozyCafes;
    case ClipMemoryType.vintageVibes:
      return locals.vintageVibes;
    case ClipMemoryType.aerialViews:
      return locals.aerialViews;
    case ClipMemoryType.artisticPortraits:
      return locals.artisticPortraits;
    case ClipMemoryType.streetFood:
      return locals.streetFood;
    case ClipMemoryType.riverCruises:
      return locals.riverCruises;
    case ClipMemoryType.playfulKids:
      return locals.playfulKids;
    case ClipMemoryType.coastalCliffs:
      return locals.coastalCliffs;
    case ClipMemoryType.candidLaughter:
      return locals.candidLaughter;
    case ClipMemoryType.groupSelfies:
      return locals.groupSelfies;
    case ClipMemoryType.birthdayJoy:
      return locals.birthdayJoy;
    case ClipMemoryType.weddingMoments:
      return locals.weddingMoments;
    case ClipMemoryType.goldenHourPortraits:
      return locals.goldenHourPortraits;
    case ClipMemoryType.concertNights:
      return locals.concertNights;
    case ClipMemoryType.poolDays:
      return locals.poolDays;
    case ClipMemoryType.picnicDays:
      return locals.picnicDays;
    case ClipMemoryType.campingMoments:
      return locals.campingMoments;
    case ClipMemoryType.babySmiles:
      return locals.babySmiles;
  }
}

class ClipMemory extends SmartMemory {
  final ClipMemoryType clipMemoryType;

  ClipMemory(
    List<Memory> memories,
    int firstDateToShow,
    int lastDateToShow,
    this.clipMemoryType, {
    super.firstCreationTime,
    super.lastCreationTime,
  }) : super(memories, MemoryType.clip, '', firstDateToShow, lastDateToShow);

  @override
  String createTitle(AppLocalizations locals, String languageCode) {
    return clipTitle(locals, clipMemoryType);
  }
}
