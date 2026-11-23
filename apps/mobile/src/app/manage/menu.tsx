import { View } from "react-native";
import { Header } from "@/components/kit";
import { MenuEditor } from "@/components/menu-editor";
import { Body, Screen, Segmented } from "@/components/ui";
import { useProperties } from "@/lib/owner";
import { space } from "@/lib/theme";

export default function OwnerMenu() {
  const { props, current, setCurrent } = useProperties();
  return (
    <Screen>
      <Header title="Food menu" sub="Residents see changes right away." />
      {props.length > 1 ? <View style={{ marginBottom: space(3) }}><Segmented value={current ?? ""} onChange={setCurrent} options={props.map((p) => ({ value: p.id, label: p.name }))} /></View> : null}
      {current ? <MenuEditor propertyId={current} /> : <Body muted>Add a property first.</Body>}
    </Screen>
  );
}
