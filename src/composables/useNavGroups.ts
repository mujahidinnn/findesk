import { computed } from "vue";
import { useAuthStore } from "@/stores/auth";
import { NAV_GROUPS, visibleGroups } from "@/lib/navigation";

export function useNavGroups() {
  const auth = useAuthStore();
  return computed(() => visibleGroups(NAV_GROUPS, (f) => auth.can(f), auth.isSuperadmin));
}
