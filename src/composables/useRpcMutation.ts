import { useMutation, useQueryClient } from "@tanstack/vue-query";
import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";

type Fns = Database["public"]["Functions"];

export function useRpcMutation<N extends keyof Fns>(name: N, invalidate: string[]) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: Fns[N]["Args"]) => {
      const { data, error } = await supabase.rpc(name, args as never);
      if (error) throw error;
      return data as Fns[N]["Returns"];
    },
    onSuccess: () => Promise.all(invalidate.map((key) => qc.invalidateQueries({ queryKey: [key] }))),
  });
}
