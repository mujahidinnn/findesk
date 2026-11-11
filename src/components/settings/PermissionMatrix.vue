<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import LoadingState from "@/components/common/LoadingState.vue";
import { useMasterRows } from "@/composables/useMasterRows";

const { t, te } = useI18n();
const roles = useMasterRows("m_roles", { order: "rank" });
const features = useMasterRows("m_features", { order: "id" });
const perms = useMasterRows("t_role_permissions");
const pending = computed(() => roles.isPending.value || features.isPending.value || perms.isPending.value);
const grant = computed(() => new Map((perms.data.value ?? []).map((p) => [`${p.role_id}:${p.feature_id}`, p])));
const ACTIONS = [["can_create", "C"], ["can_read", "R"], ["can_update", "U"], ["can_delete", "D"]] as const;
const letters = (roleId: number, featureId: number) => {
  const p = grant.value.get(`${roleId}:${featureId}`);
  return ACTIONS.map(([k, l]) => ({ l, on: !!p?.[k] }));
};
</script>

<template>
  <section class="space-y-3">
    <div>
      <h2 class="font-semibold">{{ t("settings.matrix.title") }}</h2>
      <p class="text-muted-foreground text-sm">{{ t("settings.matrix.intro") }}</p>
    </div>
    <LoadingState v-if="pending" :columns="7" />
    <div v-else class="bg-card overflow-x-auto rounded-xl border">
      <table class="w-full text-sm">
        <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
          <tr>
            <th class="px-3 py-2 font-medium">{{ t("settings.matrix.feature") }}</th>
            <th v-for="r in roles.data.value" :key="r.id" class="px-3 py-2 text-center font-medium whitespace-nowrap">{{ r.role_name }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="f in features.data.value" :key="f.id" class="border-b last:border-0">
            <td class="px-3 py-1.5 whitespace-nowrap">{{ te(`features.${f.feature_key}`) ? t(`features.${f.feature_key}`) : f.feature_name }}</td>
            <td v-for="r in roles.data.value" :key="r.id" class="px-3 py-1.5 text-center">
              <span class="inline-flex gap-0.5 font-mono text-[11px]" :aria-label="letters(r.id, f.id).filter((x) => x.on).map((x) => x.l).join('') || '-'">
                <span v-for="x in letters(r.id, f.id)" :key="x.l" :class="['w-3.5 rounded-sm', x.on ? 'bg-primary-soft text-primary-text font-semibold' : 'text-muted-foreground/30']" aria-hidden="true">{{ x.l }}</span>
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p class="text-muted-foreground text-xs">{{ t("settings.matrix.legend") }}</p>
  </section>
</template>
