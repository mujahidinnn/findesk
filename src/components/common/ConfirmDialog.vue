<script setup lang="ts">
import { Check, Trash2 } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

const open = defineModel<boolean>("open", { required: true });
defineProps<{ title: string; description?: string; confirmLabel: string; busy?: boolean; destructive?: boolean }>();
defineEmits<{ confirm: [] }>();
const { t } = useI18n();
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent class="sm:max-w-sm">
      <DialogHeader>
        <DialogTitle>{{ title }}</DialogTitle>
        <DialogDescription v-if="description">{{ description }}</DialogDescription>
      </DialogHeader>
      <slot />
      <DialogFooter>
        <Button variant="outline" @click="open = false">{{ t("common.cancel") }}</Button>
        <Button :variant="destructive ? 'destructive' : 'default'" :disabled="busy" :loading="busy" @click="$emit('confirm')">
          <component :is="destructive ? Trash2 : Check" /> {{ confirmLabel }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
