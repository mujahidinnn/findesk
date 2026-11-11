/// <reference types="vite/client" />
import { createI18n } from "vue-i18n";

type Messages = Record<string, string>;
const merge = (files: Record<string, unknown>) =>
  Object.assign({}, ...Object.values(files).map((m) => (m as { default: Messages }).default)) as Messages;
const id = merge(import.meta.glob("@/locales/id/*.json", { eager: true }));
const en = merge(import.meta.glob("@/locales/en/*.json", { eager: true }));

export const SUPPORTED_LOCALES = [
  { code: "id", label: "Indonesia" },
  { code: "en", label: "English" },
] as const;

export type Locale = (typeof SUPPORTED_LOCALES)[number]["code"];

export function browserLocale(): Locale {
  return typeof navigator !== "undefined" && navigator.language.startsWith("en") ? "en" : "id";
}

export const i18n = createI18n({
  legacy: false,
  locale: browserLocale(),
  fallbackLocale: "id",
  messages: { id, en },
});
if (typeof document !== "undefined") document.documentElement.lang = i18n.global.locale.value;

export function setLocale(locale: Locale) {
  i18n.global.locale.value = locale;
  document.documentElement.lang = locale;
}
