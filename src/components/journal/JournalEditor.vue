<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { Save, Send } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import JournalLinesEditor from "@/components/journal/JournalLinesEditor.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import type { MasterRow } from "@/composables/useMasterRows";
import { supabase } from "@/integrations/supabase/client";
import { isoDate } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";
import { blankLine, filledLines, toLine, type JournalLine } from "./lines";

const open = defineModel<boolean>("open", { required: true });
const props = defineProps<{ journal: MasterRow | null }>();
const { t } = useI18n();
const serverError = useServerError();
const saveDraft = useRpcMutation("save_journal_draft", ["t_journals", "t_journal_lines"]);
const submit = useRpcMutation("submit_journal", ["t_journals", "pending_approvals"]);

const id = ref<number | null>(null);
const form = ref({ journal_date: isoDate(), kind: "manual", memo: "", reference: "" });
const lines = ref<JournalLine[]>([]);
const loading = ref(false);
const busy = ref(false);
const KINDS = computed(() => ["manual", "opening"].map((k) => ({ value: k, label: t(`journalKinds.${k}`) })));

watch(open, async (v) => {
  if (!v) return;
  const j = props.journal;
  id.value = j?.id ?? null;
  form.value = {
    journal_date: (j?.journal_date as string) ?? isoDate(),
    kind: (j?.kind as string) ?? "manual",
    memo: (j?.memo as string) ?? "",
    reference: (j?.reference as string) ?? "",
  };
  lines.value = [blankLine(), blankLine()];
  if (!j) return;
  loading.value = true;
  const { data, error } = await supabase.from("t_journal_lines").select("*").eq("journal_id", j.id).order("line_no");
  loading.value = false;
  if (error) return toast.error(serverError(error));
  if (data.length) lines.value = data.map(toLine);
});

async function persist() {
  const header = { ...form.value, memo: form.value.memo.trim() || null, reference: form.value.reference.trim() || null };
  const rows = filledLines(lines.value);
  id.value = await saveDraft.mutateAsync({ p_id: id.value ?? undefined, p_header: header, p_lines: rows });
  return id.value;
}

async function save(andSubmit: boolean) {
  busy.value = true;
  try {
    const jid = await persist();
    if (andSubmit) {
      const res = await submit.mutateAsync({ p_id: jid });
      toast.success(res === "posted" ? t("journals.postedToast") : t("journals.submittedToast"));
    } else toast.success(t("common.saved"));
    open.value = false;
  } catch (err) {
    // The draft may already be saved (id set), so a retry updates it instead of creating a second one.
    toast.error(serverError(err));
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent class="sm:max-w-6xl">
      <DialogHeader>
        <DialogTitle>{{ journal ? t("journals.edit") : t("journals.new") }}</DialogTitle>
      </DialogHeader>
      <LoadingState v-if="loading" variant="form" />
      <form
        v-else id="journal-form" class="max-h-[70vh] space-y-4 overflow-y-auto p-1"
        @submit.prevent="save(($event as SubmitEvent).submitter?.getAttribute('value') === 'submit')"
      >
        <div class="grid gap-3 sm:grid-cols-4">
          <div class="space-y-1.5">
            <Label for="je-date">{{ t("common.date") }}</Label>
            <input id="je-date" v-model="form.journal_date" type="date" required :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5">
            <Label for="je-kind">{{ t("journals.kind") }}</Label>
            <AppSelect id="je-kind" :model-value="form.kind" :options="KINDS" required @update:model-value="form.kind = $event ?? 'manual'" />
          </div>
          <div class="space-y-1.5 sm:col-span-2">
            <Label for="je-ref">{{ t("common.reference") }}</Label>
            <input id="je-ref" v-model="form.reference" :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5 sm:col-span-4">
            <Label for="je-memo">{{ t("journals.memo") }}</Label>
            <input id="je-memo" v-model="form.memo" required :class="FIELD_CLASS" />
          </div>
        </div>
        <JournalLinesEditor v-model="lines" />
      </form>
      <DialogFooter>
        <Button variant="outline" @click="open = false">{{ t("common.cancel") }}</Button>
        <Button type="submit" form="journal-form" value="draft" variant="outline" :disabled="busy || loading" :loading="busy"><Save /> {{ t("journals.saveDraft") }}</Button>
        <Button type="submit" form="journal-form" value="submit" class="active:scale-95" :disabled="busy || loading" :loading="busy"><Send /> {{ t("journals.saveSubmit") }}</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
