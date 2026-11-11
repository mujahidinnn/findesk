import { computed, onScopeDispose, watch } from "vue";
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/vue-query";
import { supabase } from "@/integrations/supabase/client";
import { subscribeShared } from "@/lib/realtimeSubscription";
import { useAuthStore } from "@/stores/auth";

const QK = ["notifications"] as const;
export const NOTIFICATION_PAGE = 30;

export function useNotifications() {
  const auth = useAuthStore();
  const qc = useQueryClient();
  const userId = computed(() => auth.user?.id);

  const query = useInfiniteQuery({
    queryKey: computed(() => [...QK, "list", userId.value]),
    enabled: computed(() => !!userId.value),
    initialPageParam: 0,
    queryFn: async ({ pageParam }) => {
      const { data, error } = await supabase
        .from("t_notifications")
        .select("*")
        .order("created_at", { ascending: false })
        .range(pageParam, pageParam + NOTIFICATION_PAGE - 1);
      if (error) throw error;
      return data;
    },
    getNextPageParam: (last, all) => (last.length < NOTIFICATION_PAGE ? undefined : all.length * NOTIFICATION_PAGE),
  });
  const unread = useQuery({
    queryKey: computed(() => [...QK, "unread", userId.value]),
    enabled: computed(() => !!userId.value),
    queryFn: async () => {
      const { count, error } = await supabase.from("t_notifications").select("id", { count: "exact", head: true }).eq("is_read", false);
      if (error) throw error;
      return count ?? 0;
    },
  });

  let stop: (() => void) | undefined;
  watch(
    userId,
    (id) => {
      stop?.();
      stop = id
        ? subscribeShared(`notifications-${id}`, (ch) =>
            ch.on(
              "postgres_changes",
              { event: "INSERT", schema: "public", table: "t_notifications", filter: `user_id=eq.${id}` },
              () => qc.invalidateQueries({ queryKey: QK }),
            ),
          )
        : undefined;
    },
    { immediate: true },
  );
  onScopeDispose(() => stop?.());

  return { query, unread };
}

export function useMarkNotificationsRead() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (ids?: number[]) => {
      let q = supabase.from("t_notifications").update({ is_read: true }).eq("is_read", false);
      if (ids) q = q.in("id", ids);
      const { error } = await q;
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: QK }),
  });
}

export function useClearReadNotifications() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("t_notifications").delete().eq("is_read", true);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: QK }),
  });
}
