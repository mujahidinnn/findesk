<script setup lang="ts">
import { LogOut } from "@lucide/vue";
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

const open = defineModel<boolean>("open", { required: true });
const props = defineProps<{ onConfirm: () => Promise<void> }>();
const { t } = useI18n();
const busy = ref(false);

async function confirm() {
  busy.value = true;
  try {
    await props.onConfirm();
    open.value = false;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent class="sm:max-w-sm">
      <DialogHeader>
        <DialogTitle>{{ t("shell.signOutTitle") }}</DialogTitle>
        <DialogDescription>{{ t("shell.signOutBody") }}</DialogDescription>
      </DialogHeader>
      <DialogFooter>
        <Button variant="outline" @click="open = false">{{ t("common.cancel") }}</Button>
        <Button variant="destructive" :disabled="busy" :loading="busy" @click="confirm"><LogOut /> {{ t("shell.signOut") }}</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
