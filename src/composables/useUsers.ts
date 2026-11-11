import { useMutation, useQuery, useQueryClient } from "@tanstack/vue-query";
import { supabase } from "@/integrations/supabase/client";

const QK = ["users-with-email"] as const;

export function useUsers() {
  return useQuery({
    queryKey: QK,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("get_users_with_email");
      if (error) throw error;
      return data;
    },
  });
}

export function useCreateUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (body: { email: string; password: string; full_name: string; role_id: number }) => {
      const { data, error } = await supabase.functions.invoke("create-user", { body });
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: QK }),
  });
}

export function useSetUserRole() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, role_id }: { id: string; role_id: number }) => {
      const { error } = await supabase.from("profiles").update({ role_id }).eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: QK }),
  });
}

export function useSetUserBanned() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, banned }: { id: string; banned: boolean }) => {
      const { error } = await supabase.functions.invoke(banned ? "delete-user" : "reactivate-user", {
        body: { user_id: id },
      });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: QK }),
  });
}
