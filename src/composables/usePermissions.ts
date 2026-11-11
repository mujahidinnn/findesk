import { storeToRefs } from "pinia";
import { useAuthStore } from "@/stores/auth";

export function usePermissions() {
  const auth = useAuthStore();
  const { isAdmin, isSuperadmin } = storeToRefs(auth);
  return { can: auth.can, isAdmin, isSuperadmin };
}
