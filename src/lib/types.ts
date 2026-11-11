import type { Tables } from "@/integrations/supabase/types";

export type Action = "create" | "read" | "update" | "delete";

export type Feature = Tables<"m_features">;
export type RolePermission = Tables<"t_role_permissions">;
export type UserOverride = Tables<"t_user_access_override">;
export type Notification = Tables<"t_notifications">;

export interface FeaturePermission {
  can_create: boolean;
  can_read: boolean;
  can_update: boolean;
  can_delete: boolean;
}

export type PermissionMap = Record<string, FeaturePermission>;

export const PROFILE_COLUMNS =
  "id, role_id, full_name, avatar_url, locale, employee_code, is_superadmin, role:m_roles(id, role_name, rank)";

export interface Profile {
  id: string;
  role_id: number | null;
  full_name: string | null;
  avatar_url: string | null;
  locale: "id" | "en" | null;
  employee_code: string | null;
  is_superadmin: boolean;
  role: { id: number; role_name: string; rank: number } | null;
}
