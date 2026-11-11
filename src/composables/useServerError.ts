import { useI18n } from "vue-i18n";
import { serverErrorKey } from "@/lib/serverError";

export function useServerError() {
  const { t, te } = useI18n();
  return (err: unknown) => {
    const key = `serverErrors.${serverErrorKey(err as { code?: string; message?: string })}`;
    return t(te(key) ? key : "serverErrors.UNKNOWN");
  };
}
