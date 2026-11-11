import { computed, toValue, type MaybeRefOrGetter } from "vue";
import { useQuery } from "@tanstack/vue-query";
import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";

type Fns = Database["public"]["Functions"];

export function useRpcQuery<N extends keyof Fns>(name: N, args: MaybeRefOrGetter<Fns[N]["Args"] | null>) {
  return useQuery({
    queryKey: computed(() => [name, toValue(args)]),
    enabled: computed(() => toValue(args) != null),
    queryFn: async () => {
      const { data, error } = await supabase.rpc(name, toValue(args) as never);
      if (error) throw error;
      return data as Fns[N]["Returns"];
    },
  });
}
