/** Origin Living mobile design tokens: bright cream + pure black, same as the website. */
export const color = {
  bg: "#fbf8f1",
  card: "#ffffff",
  cream: "#f2ede2",
  ink: "#000000",
  ink2: "#3d3a35",
  ink3: "#7a756c",
  line: "#e9e3d6",
  ok: "#1f7a4d",
  okBg: "#e6f3ec",
  warn: "#9a5b00",
  warnBg: "#fbf0dc",
  bad: "#b3261e",
  badBg: "#fbe7e5",
} as const;

export const radius = { sm: 12, md: 18, lg: 26, pill: 999 } as const;
export const space = (n: number) => n * 4;

/** iOS uses SF Pro automatically (system font); Android uses Roboto. Weights tuned per platform. */
export const type = {
  hero: { fontSize: 40, lineHeight: 42, fontWeight: "700", letterSpacing: -1.6 },
  h1: { fontSize: 30, lineHeight: 34, fontWeight: "700", letterSpacing: -1 },
  h2: { fontSize: 22, lineHeight: 27, fontWeight: "600", letterSpacing: -0.5 },
  body: { fontSize: 16, lineHeight: 22, fontWeight: "400" },
  small: { fontSize: 13, lineHeight: 18, fontWeight: "400" },
  label: { fontSize: 14, lineHeight: 18, fontWeight: "600" },
} as const;

export const rupees = (n: number | null | undefined) => {
  const v = Number(n ?? 0);
  return `${v < 0 ? "-" : ""}₹${Math.abs(v).toLocaleString("en-IN", { maximumFractionDigits: 0 })}`;
};
