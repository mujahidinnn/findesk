<script setup lang="ts">
import { ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import { Label } from "@/components/ui/label";
import { FIELD_CLASS } from "@/lib/utils";

const open = defineModel<boolean>("open", { required: true });
defineProps<{ title: string; description?: string; confirmLabel: string; busy?: boolean; destructive?: boolean }>();
const emit = defineEmits<{ confirm: [reason: string] }>();
const { t } = useI18n();
const reason = ref("");
watch(open, (v) => v && (reason.value = ""));
</script>

<template>
  <ConfirmDialog
    v-model:open="open"
    :title="title"
    :description="description"
    :confirm-label="confirmLabel"
    :busy="busy || !reason.trim()"
    :destructive="destructive"
    @confirm="emit('confirm', reason.trim())"
  >
    <div class="space-y-1.5">
      <Label for="reason-input">{{ t("common.reason") }}</Label>
      <textarea id="reason-input" v-model="reason" rows="3" required :class="[FIELD_CLASS, 'h-auto py-2']" />
    </div>
  </ConfirmDialog>
</template>
