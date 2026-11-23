export const ROOM_TYPES = [
  { value: "SINGLE", label: "Single", beds: 1 },
  { value: "DOUBLE_SHARING", label: "2 sharing", beds: 2 },
  { value: "TRIPLE_SHARING", label: "3 sharing", beds: 3 },
  { value: "FOUR_SHARING", label: "4 sharing", beds: 4 },
] as const;
export const roomTypeLabel = (t?: string) => ROOM_TYPES.find((r) => r.value === t)?.label ?? (t ?? "").replace(/_/g, " ").toLowerCase();
