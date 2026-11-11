import { useMutation, useQueryClient } from "@tanstack/vue-query";
import type { SupabaseClient } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";
import type { MasterTable } from "@/composables/useMasterRows";

const db = supabase as unknown as SupabaseClient;

export function useCreateDocument(header: MasterTable, lines: MasterTable, parentKey: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (doc: { header: Record<string, unknown>; lines: Record<string, unknown>[] }) => {
      const head = await db.from(header).insert(doc.header).select("id").single();
      if (head.error) throw head.error;
      const id = head.data.id as number;
      if (doc.lines.length) {
        const { error } = await db.from(lines).insert(doc.lines.map((l) => ({ ...l, [parentKey]: id })));
        if (error) {
          await db.from(header).delete().eq("id", id);
          throw error;
        }
      }
      return id;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: [header] }),
  });
}
