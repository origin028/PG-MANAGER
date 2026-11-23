import { View } from "react-native";
import { MenuEditor } from "@/components/menu-editor";
import { Body, Screen, Segmented, Title } from "@/components/ui";
import { useProperties } from "@/lib/owner";
import { space } from "@/lib/theme";

export default function KitchenMenu() {
  const { props, current, setCurrent } = useProperties();
  return (
    <Screen>
      <Title sub="Changes show up in residents' apps right away.">Weekly menu</Title>
      {props.length > 1 ? <View style={{ marginBottom: space(3) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      {current ? <MenuEditor propertyId={current} /> : <Body muted>No home assigned.</Body>}
    </Screen>
  );
}
