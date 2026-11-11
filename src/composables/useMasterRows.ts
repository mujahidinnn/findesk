import { computed, toValue, type MaybeRefOrGetter } from "vue";
import { useMutation, useQuery, useQueryClient } from "@tanstack/vue-query";
import type { SupabaseClient } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";

export type MasterTable = keyof Database["public"]["Tables"];
export type MasterRow = Record<string, unknown> & { id: number };

const db = supabase as unknown as SupabaseClient;

interface Options {
  filter?: MaybeRefOrGetter<Record<string, unknown> | undefined>;
  columns?: string;
  order?: string;
  descending?: boolean;
  enabled?: MaybeRefOrGetter<boolean>;
}

// ponytail: one page of 1000 rows filtered in the browser; switch to server paging when a master outgrows it.
export function useMasterRows(table: MasterTable, opts: Options = {}) {
  const filter = computed(() => toValue(opts.filter) ?? {});
  return useQuery({
    queryKey: computed(() => [table, filter.value, opts.columns ?? "*", opts.order ?? "id"]),
    enabled: computed(() => toValue(opts.enabled) ?? true),
    queryFn: async () => {
      const { data, error } = await db
        .from(table)
        .select(opts.columns ?? "*")
        .match(filter.value)
        .order(opts.order ?? "id", { ascending: !opts.descending })
        .limit(1000);
      if (error) throw error;
      return data as unknown as MasterRow[];
    },
  });
}

export function useSaveMasterRow(table: MasterTable) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, values }: { id?: number; values: Record<string, unknown> }) => {
      const { error } = id ? await db.from(table).update(values).eq("id", id) : await db.from(table).insert(values);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: [table] }),
  });
}

export function useDeleteMasterRow(table: MasterTable) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: number) => {
      const { error } = await db.from(table).delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: [table] }),
  });
}

export function useMasterOptions(table: MasterTable, label: (row: MasterRow) => string, opts: Options = {}) {
  const rows = useMasterRows(table, opts);
  return computed(() => (rows.data.value ?? []).map((r) => ({ value: r.id, label: label(r) })));
}
