<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Building2, CalendarClock, Coins, Link2, UserCog } from "@lucide/vue";
import CrudTable, { type CrudField } from "@/components/common/CrudTable.vue";
import TabBar from "@/components/common/TabBar.vue";
import AccountMapTab from "@/components/settings/AccountMapTab.vue";
import CompanyForm from "@/components/settings/CompanyForm.vue";
import CurrenciesTab from "@/components/settings/CurrenciesTab.vue";
import PermissionMatrix from "@/components/settings/PermissionMatrix.vue";
import UsersTab from "@/components/settings/UsersTab.vue";
import { usePermissions } from "@/composables/usePermissions";
import { useTabParam } from "@/composables/useTabParam";

const { t } = useI18n();
const { can } = usePermissions();
const ALL = [
  { key: "company", icon: Building2, ok: () => can("settings", "read") },
  { key: "accountMap", icon: Link2, ok: () => can("settings", "read") },
  { key: "currencies", icon: Coins, ok: () => can("settings", "read") },
  { key: "terms", icon: CalendarClock, ok: () => can("settings", "read") },
  { key: "users", icon: UserCog, ok: () => can("users", "read") },
] as const;
type Key = (typeof ALL)[number]["key"];
const visible = computed(() => ALL.filter((x) => x.ok()));
const tab = useTabParam<Key>(() => visible.value.map((x) => x.key));
const tabs = computed(() => visible.value.map((x) => ({ key: x.key, label: t(`settings.tabs.${x.key}`), icon: x.icon })));

const termFields = computed<CrudField[]>(() => [
  { key: "code", label: t("common.code"), required: true, upper: true, mono: true, pattern: "[A-Za-z0-9][A-Za-z0-9_\\-]*" },
  { key: "name", label: t("common.name"), required: true },
  { key: "days", label: t("settings.terms.days"), type: "number", step: "1", required: true, default: 0, hint: t("settings.terms.daysHint") },
  { key: "is_active", label: t("common.active"), type: "boolean", default: true },
]);
</script>

<template>
  <div class="space-y-6">
    <TabBar v-model="tab" :tabs="tabs" />
    <CompanyForm v-if="tab === 'company'" />
    <AccountMapTab v-else-if="tab === 'accountMap'" />
    <CurrenciesTab v-else-if="tab === 'currencies'" />
    <CrudTable v-else-if="tab === 'terms'" table="m_payment_terms" feature="settings" :title="t('settings.terms.title')" :fields="termFields" order="days" />
    <template v-else-if="tab === 'users'">
      <UsersTab />
      <PermissionMatrix />
    </template>
  </div>
</template>
