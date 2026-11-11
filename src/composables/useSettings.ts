import { useMutation, useQuery, useQueryClient } from "@tanstack/vue-query";
import { supabase } from "@/integrations/supabase/client";
import type { TablesUpdate } from "@/integrations/supabase/types";

const QK = ["m_settings"] as const;

export function useSettings() {
  return useQuery({
    queryKey: QK,
    queryFn: async () => {
      const { data, error } = await supabase.from("m_settings").select("*").eq("id", 1).single();
      if (error) throw error;
      return data;
    },
  });
}

export function useUpdateSettings() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: TablesUpdate<"m_settings">) => {
      const { error } = await supabase.from("m_settings").update(values).eq("id", 1);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: QK }),
  });
}
