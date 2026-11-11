import { enUS, id } from "date-fns/locale";
import { i18n } from "./i18n";

export const dateLocale = () => (i18n.global.locale.value === "en" ? enUS : id);
