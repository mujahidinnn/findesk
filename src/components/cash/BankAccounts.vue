<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { BookOpen, Coins, Landmark, Wallet } from "@lucide/vue";
import CrudTable, { type CrudField } from "@/components/common/CrudTable.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import { useAccountOptions, useCurrencyOptions } from "@/composables/useLookups";
import { useMasterRows } from "@/composables/useMasterRows";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { formatMoney, isoDate } from "@/lib/format";

defineProps<{ base: string }>();
const { t } = useI18n();

const banks = useMasterRows("m_bank_accounts", { order: "code" });
const summary = useRpcQuery("bank_balances", () => ({ p_as_of: isoDate() }));
const balances = computed(() => new Map((summary.data.value ?? []).map((b) => [b.id, b])));
const ICON = { bank: Landmark, cash: Wallet, petty: Coins } as const;

const glAccounts = useAccountOptions({ subtypes: ["cash", "bank"] });
const currencies = useCurrencyOptions();
const fields = computed<CrudField[]>(() => [
  { key: "code", label: t("common.code"), required: true, upper: true, mono: true },
  { key: "name", label: t("common.name"), required: true },
  { key: "kind", label: t("cash.bank.kind"), type: "select", required: true, default: "bank", options: (["bank", "cash", "petty"] as const).map((k) => ({ value: k, label: t(`cash.bank.kinds.${k}`) })) },
  { key: "bank_name", label: t("cash.bank.bankName") },
  { key: "account_no", label: t("cash.bank.accountNo"), mono: true },
  { key: "account_holder", label: t("cash.bank.holder"), hideInTable: true },
  { key: "currency", label: t("common.currency"), type: "select", required: true, default: "IDR", options: currencies.value, lockOnEdit: true },
  { key: "gl_account_id", label: t("cash.bank.glAccount"), type: "select", required: true, options: glAccounts.options.value, hint: t("cash.bank.glHint") },
  { key: "is_active", label: t("common.active"), type: "boolean", default: true },
]);
</script>

<template>
  <div class="space-y-6">
    <LoadingState v-if="banks.isPending.value" variant="cards" />
    <div v-else class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
      <article v-for="b in (banks.data.value ?? []).filter((x) => x.is_active)" :key="b.id" class="bg-card flex flex-col gap-3 rounded-xl border p-4">
        <div class="flex items-start gap-3">
          <span class="bg-primary-soft text-primary-text flex size-10 shrink-0 items-center justify-center rounded-xl">
            <component :is="ICON[b.kind as keyof typeof ICON] ?? Landmark" class="size-5" />
          </span>
          <div class="min-w-0 flex-1">
            <p class="truncate font-semibold">{{ b.name }}</p>
            <p class="text-muted-foreground truncate text-xs">
              <span class="font-mono">{{ b.code }}</span>
              <template v-if="b.bank_name"> · {{ b.bank_name }}</template>
              <template v-if="b.account_no"> · <span class="font-mono">{{ b.account_no }}</span></template>
            </p>
          </div>
          <StatusBadge tone="muted">{{ t(`cash.bank.kinds.${b.kind}`) }}</StatusBadge>
        </div>
        <div class="border-t border-dashed pt-3">
          <p class="text-muted-foreground text-xs">{{ t("cash.bank.balance") }}</p>
          <p v-if="summary.isPending.value" class="shimmer mt-1 h-7 w-40" />
          <p v-else-if="summary.isError.value" class="text-muted-foreground text-sm">{{ t("common.loadFailed") }}</p>
          <template v-else>
            <p class="text-xl font-semibold tabular-nums">{{ formatMoney(balances.get(b.id)?.[b.currency === base ? "base" : "fc"] ?? 0, String(b.currency)) }}</p>
            <p v-if="b.currency !== base" class="text-muted-foreground text-xs tabular-nums">≈ {{ formatMoney(balances.get(b.id)?.base ?? 0, base) }}</p>
          </template>
        </div>
        <RouterLink :to="{ path: '/ledger', query: { account: String(b.gl_account_id) } }" class="text-primary-text mt-auto inline-flex items-center gap-1.5 text-xs font-medium hover:underline">
          <BookOpen class="size-3.5" /> {{ t("cash.bank.openLedger") }}
        </RouterLink>
      </article>
    </div>

    <CrudTable table="m_bank_accounts" feature="cash-bank" :title="t('cash.bank.title')" :fields="fields" order="code" />
  </div>
</template>
