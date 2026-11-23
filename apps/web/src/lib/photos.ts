/**
 * Photography from Unsplash (free under the Unsplash License), picked to match a PG:
 * bright bedrooms, Indian home food, students, a common room, a residential building.
 * Swap for the PG's own photos before launch; keep the same keys.
 */
const U = (id: string) => (w: number, h: number) =>
  `https://images.unsplash.com/photo-${id}?w=${w}&h=${h}&fit=crop&auto=format&q=75`;

export const IMG = {
  heroBed: U("1617325247661-675ab4b64ae2"),     // bright minimal bed
  roomWhite: U("1595526114035-0d45ed16cfbf"),   // white bedroom
  roomHotel: U("1631049307264-da0ec9d70304"),   // neat single room
  roomGrey: U("1522771739844-6a9f6d5f14af"),    // calm bedroom
  thali: U("1546833999-b9f581a1996d"),          // Indian thali
  paneer: U("1567188040759-fb8a883dc6d8"),      // paneer tikka
  curry: U("1585937421612-70a008356fbe"),       // curry
  samosa: U("1601050690597-df0568f70950"),      // samosa
  friends: U("1522202176988-66273c2fd55f"),     // students together
  studying: U("1523240795612-9a054b0db644"),    // studying together
  common: U("1524758631624-e2822e304c36"),      // bright lounge
  living: U("1493809842364-78817add7ffb"),      // bright living room
  building: U("1545324418-cc1a3fa10c00"),       // residential building
  lock: U("1558002038-1055907df827"),           // smart lock
  cleaning: U("1527515637462-cff94eecc1ac"),    // housekeeping
} as const;
