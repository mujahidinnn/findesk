import { i18n } from "@/lib/i18n";

// Seeded master names (chart of accounts `coa`, cost centers `cc`) are Indonesian. Show the locale's version only while
// the stored name is still the seed value, so a name the user edited is never overwritten.
function seedName(ns: "coa" | "cc", code: string, name: string) {
  const { te, t, locale, getLocaleMessage } = i18n.global;
  const seed = (getLocaleMessage("id") as Record<string, Record<string, string> | undefined>)[ns]?.[code];
  return locale.value !== "id" && seed === name && te(`${ns}.${code}`) ? t(`${ns}.${code}`) : name;
}
export const accountName = (code: string, name: string) => seedName("coa", code, name);
export const costCenterName = (code: string, name: string) => seedName("cc", code, name);
