import { useEffect, useState } from "react";
import { View } from "react-native";
import { Body, Segmented, Skeleton } from "@/components/ui";
import { api } from "@/lib/api";

export type FreeBed = { id: string; room_id: string; room_number?: string; bed_number: string; monthly_rent?: number };

/** Chips of free beds in a home. Calls back with the chosen bed (and its suggested rent). */
export function BedPicker({ propertyId, value, onChange }: { propertyId?: string | null; value: string; onChange: (bed: FreeBed) => void }) {
  const [beds, setBeds] = useState<FreeBed[] | null>(null);
  useEffect(() => {
    if (!propertyId) return;
    let alive = true;
    api<FreeBed[]>(`/beds?property_id=${propertyId}&status=AVAILABLE`).then((b) => alive && setBeds(b)).catch(() => alive && setBeds([]));
    return () => { alive = false; };
  }, [propertyId]);
  if (beds === null) return <Skeleton h={40} />;
  if (!beds.length) return <Body muted>No free beds. Add beds in Rooms first.</Body>;
  return (
    <View>
      <Segmented value={value} onChange={(id) => { const b = beds.find((x) => x.id === id); if (b) onChange(b); }}
        options={beds.map((b) => ({ value: b.id, label: `Room ${b.room_number ?? "?"} · ${b.bed_number}` }))} />
    </View>
  );
}
