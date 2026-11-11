<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { Ban, Save, UserCheck, UserPlus } from "@lucide/vue";
import PasswordInput from "@/components/common/PasswordInput.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import TablePager from "@/components/common/TablePager.vue";
import { rowText, usePaged } from "@/composables/usePaged";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useMasterOptions } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useServerError } from "@/composables/useServerError";
import { useCreateUser, useSetUserBanned, useSetUserRole, useUsers } from "@/composables/useUsers";
import { useAuthStore } from "@/stores/auth";

// ponytail: per-feature access overrides (t_user_access_override) are not editable here yet;
const { t } = useI18n();
const auth = useAuthStore();
const serverError = useServerError();
const { can } = usePermissions();
const initials = (name: string | null) => (name ?? "?").split(" ").map((w) => w[0]).slice(0, 2).join("").toUpperCase();
const users = useUsers();
const roleOptions = useMasterOptions("m_roles", (r) => String(r.role_name), { order: "rank" });

const search = ref("");
const roleFilter = ref<number | null>(null);
const stateFilter = ref<"active" | "banned" | null>(null);
const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  return (users.data.value ?? []).filter(
    (u) =>
      (!q || rowText(u).includes(q)) &&
      (roleFilter.value == null || u.role_id === roleFilter.value) &&
      (!stateFilter.value || (stateFilter.value === "banned") === !!u.banned_until),
  );
});
const paged = usePaged(filtered);

const createUser = useCreateUser();
const setRole = useSetUserRole();
const setBanned = useSetUserBanned();

const myRank = computed(() => auth.profile?.role?.rank);
const assignableRoles = computed(() => roleOptions.value.filter((r) => myRank.value == null || Number(r.value) > myRank.value!));

const run = async (action: () => Promise<unknown>) => {
  try {
    await action();
    toast.success(t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
  }
};

const createOpen = ref(false);
const form = ref({ email: "", password: "", full_name: "", role_id: null as number | null });
function startCreate() {
  form.value = { email: "", password: "", full_name: "", role_id: null };
  createOpen.value = true;
}
const submitCreate = () =>
  run(async () => {
    await createUser.mutateAsync(form.value as never);
    createOpen.value = false;
  });

</script>

<template>
  <section class="space-y-3">
    <div class="toolbar">
      <h2 class="mr-auto font-semibold">{{ t("users.users") }}</h2>
      <AppSelect v-model="roleFilter" :options="roleOptions" :null-label="`${t('users.role')}: ${t('common.all')}`" class="w-44" :aria-label="t('users.role')" />
      <AppSelect
        v-model="stateFilter"
        :options="[{ value: 'active', label: t('common.active') }, { value: 'banned', label: t('users.banned') }]"
        :null-label="t('common.allStatuses')"
        class="w-36"
        :aria-label="t('common.status')"
      />
      <Input v-model="search" type="search" class="h-9 w-48" :placeholder="t('common.search')" :aria-label="t('common.search')" />
      <Button v-if="can('users', 'create')" size="sm" @click="startCreate"><UserPlus /> {{ t("users.newUser") }}</Button>
    </div>

    <LoadingState v-if="users.isPending.value" :columns="6" />
    <div v-else class="bg-card overflow-x-auto rounded-xl border">
      <table v-stack class="w-full text-sm">
        <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
          <tr class="[&>th]:px-3 [&>th]:py-2 [&>th]:font-medium">
            <th>{{ t("common.name") }}</th>
            <th v-if="auth.isAdmin">{{ t("login.email") }}</th>
            <th>{{ t("users.employeeCode") }}</th>
            <th>{{ t("users.role") }}</th>
            <th>{{ t("common.active") }}</th>
            <th class="w-px"><span class="sr-only">{{ t("common.actions") }}</span></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in paged.rows.value" :key="row.id" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
            <td>
              <span class="flex items-center gap-2">
                <img v-if="row.avatar_url" :src="row.avatar_url" alt="" class="size-7 shrink-0 rounded-full object-cover" />
                <span v-else class="bg-brand-100 text-brand-800 dark:bg-brand-900 dark:text-brand-200 flex size-7 shrink-0 items-center justify-center rounded-full text-[10px] font-bold">{{ initials(row.full_name) }}</span>
                {{ row.full_name }}
              </span>
            </td>
            <td v-if="auth.isAdmin" class="font-mono text-xs">{{ row.email }}</td>
            <td class="font-mono text-xs">{{ row.employee_code }}</td>
            <td>
              <AppSelect
                :model-value="row.role_id as number"
                :options="row.id === auth.user?.id ? roleOptions : assignableRoles"
                size="sm"
                class="w-40"
                :disabled="row.id === auth.user?.id || !can('users', 'update') || setRole.isPending.value"
                @update:model-value="run(() => setRole.mutateAsync({ id: row.id, role_id: Number($event) }))"
              />
            </td>
            <td>
              <StatusBadge :tone="row.banned_until ? 'danger' : 'success'">
                {{ row.banned_until ? t("users.banned") : t("common.active") }}
              </StatusBadge>
            </td>
            <td>
              <div class="flex justify-end gap-1">
                <Button
                  v-if="row.id !== auth.user?.id && can('users', 'delete')"
                  variant="ghost-destructive"
                  size="icon"
                  class="size-8"
                  :tooltip="row.banned_until ? t('users.reactivate') : t('users.deactivate')"
                  :disabled="setBanned.isPending.value"
                  :loading="setBanned.isPending.value && JSON.stringify(setBanned.variables.value) === JSON.stringify({ id: row.id, banned: !row.banned_until })"
                  @click="run(() => setBanned.mutateAsync({ id: row.id, banned: !row.banned_until }))"
                >
                  <component :is="row.banned_until ? UserCheck : Ban" />
                </Button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <TablePager v-if="!users.isPending.value" v-model:page="paged.page.value" v-model:per-page="paged.perPage.value" :total="paged.total.value" :pages="paged.pages.value" />

    <Dialog v-model:open="createOpen">
      <DialogContent class="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>{{ t("users.newUser") }}</DialogTitle>
        </DialogHeader>
        <form id="user-form" class="space-y-3" @submit.prevent="submitCreate">
          <div class="space-y-1.5">
            <Label for="user-name">{{ t("profile.fullName") }}</Label>
            <Input id="user-name" v-model="form.full_name" required maxlength="120" />
          </div>
          <div class="space-y-1.5">
            <Label for="user-email">{{ t("login.email") }}</Label>
            <Input id="user-email" v-model="form.email" type="email" required />
          </div>
          <div class="space-y-1.5">
            <Label for="user-password">{{ t("password.new") }}</Label>
            <PasswordInput id="user-password" v-model="form.password" required autocomplete="new-password" />
            <p class="text-muted-foreground text-xs">{{ t("password.rule") }}</p>
          </div>
          <div class="space-y-1.5">
            <Label for="user-role">{{ t("users.role") }}</Label>
            <AppSelect id="user-role" v-model="form.role_id" :options="assignableRoles" placeholder="-" required />
          </div>
        </form>
        <DialogFooter>
          <Button variant="outline" @click="createOpen = false">{{ t("common.cancel") }}</Button>
          <Button type="submit" form="user-form" :disabled="createUser.isPending.value" :loading="createUser.isPending.value"><Save /> {{ t("common.save") }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </section>
</template>
