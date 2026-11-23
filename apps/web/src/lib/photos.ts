/**
 * Placeholder photography (picsum.photos, free to use) chosen to fit a PG:
 * beds, rooms, food, a front door. Replace with the PG's own photos before launch.
 */
export const photo = (id: number, w: number, h: number) => `https://picsum.photos/id/${id}/${w}/${h}`;

export const P = {
  bed: 691,        // made bed, morning mug
  reading: 755,    // cosy evening mug
  dining: 625,     // dining room
  desk: 445,       // desk by a window
  meal: 488,       // bowl of food
  table: 835,      // shared table spread
  mug: 755,        // cosy mug
  door: 946,       // front door
  cafe: 513,       // people together
} as const;
