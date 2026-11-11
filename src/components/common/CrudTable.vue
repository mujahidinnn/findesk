<script setup lang="ts">
import { computed, ref, type Component } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { ImageOff, LayoutGrid, Package, Pencil, Plus, RefreshCw, Rows3, Save, Trash2, X } from "@lucide/vue";
import { useLocalStorage } from "@vueuse/core";
import MoneyInput from "@/components/common/MoneyInput.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import TablePager from "@/components/common/TablePager.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  useDeleteMasterRow,
  useMasterRows,
  useSaveMasterRow,
  type MasterRow,
  type MasterTable,
} from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { supabase } from "@/integrations/supabase/client";
import { useServerError } from "@/composables/useServerError";
import { FIELD_CLASS } from "@/lib/utils";
import { rowText, usePaged } from "@/composables/usePaged";

export interface CrudField {
  key: string;
  label: string;
  type?: "text" | "number" | "select" | "boolean" | "textarea" | "date" | "time" | "image" | "images" | "money";
  bucket?: string;
  options?: { value: string | number; label: string }[];
  required?: boolean;
  pattern?: string;
  upper?: boolean;
  step?: string;
  default?: unknown;
  hint?: string;
  hideInTable?: boolean;
  hideInForm?: boolean;
  lockOnEdit?: boolean;
  mono?: boolean;
  transform?: (text: string) => string;
}

const props = defineProps<{
  table: MasterTable;
  fields: CrudField[];
  feature: string;
  title: string;
  filter?: Record<string, unknown>;
  insertDefaults?: Record<string, unknown>;
  order?: string;
  descending?: boolean;
  searchKeys?: string[];
  readonly?: boolean;
  appendOnly?: boolean;
  grid?: { title: string; subtitle?: string[]; image?: string };
  placeholder?: Component;
}>();

const { t } = useI18n();
const { can } = usePermissions();
const serverError = useServerError();

const rows = useMasterRows(props.table, { filter: () => props.filter, order: props.order, descending: props.descending });
const save = useSaveMasterRow(props.table);
const remove = useDeleteMasterRow(props.table);

const search = ref("");
const editing = ref<MasterRow | null>(null);
const formOpen = ref(false);
const form = ref<Record<string, unknown>>({});
const deleting = ref<MasterRow | null>(null);
const uploading = ref(false);
const view = useLocalStorage<"table" | "grid">(`crud-view-${props.table}`, "table");
const showGrid = computed(() => !!props.grid && view.value === "grid");
const brokenImg = ref(new Set<number>());
const markBroken = (id: number) => (brokenImg.value = new Set(brokenImg.value).add(id));
const imageOf = (row: MasterRow) => (props.grid?.image && row[props.grid.image] && !brokenImg.value.has(row.id) ? String(row[props.grid.image]) : null);

const tableFields = computed(() => props.fields.filter((f) => !f.hideInTable && !(props.grid?.image === f.key && props.fields.some((x) => x.key === props.grid?.title))));
const formFields = computed(() => props.fields.filter((f) => !f.hideInForm));
const wide = computed(() => formFields.value.length > 5);
const fullRow = (f: CrudField) => f.type === "textarea" || f.type === "image" || f.type === "images" || f.type === "boolean";
const filterFields = computed(() => tableFields.value.filter((f) => (f.type === "select" && f.options?.length) || f.type === "boolean").slice(0, 3));
const filters = ref<Record<string, string | number | null>>({});
const cellKey = (r: MasterRow, k: string) => (fieldByKey(k)?.type === "boolean" ? (r[k] ? "1" : "0") : r[k]);
const fieldByKey = (k: string) => props.fields.find((f) => f.key === k);
const visible = computed(() => {
  const q = search.value.trim().toLowerCase();
  const keys = props.searchKeys ?? [];
  return (rows.data.value ?? []).filter(
    (r) =>
      (!q || (keys.length ? keys.some((k) => String(r[k] ?? "").toLowerCase().includes(q)) : rowText(r).includes(q))) &&
      Object.entries(filters.value).every(([k, v]) => v == null || String(cellKey(r, k)) === String(v)),
  );
});
const paged = usePaged(visible);
const filterOptions = (f: CrudField) =>
  f.type === "boolean" ? [{ value: "1", label: t("common.yes") }, { value: "0", label: t("common.no") }] : (f.options ?? []);

function display(field: CrudField, row: MasterRow) {
  const v = row[field.key];
  if (field.type === "select") return field.options?.find((o) => o.value === v)?.label ?? "";
  if (field.type === "money") return v == null ? "" : "Rp\u00a0" + Number(v).toLocaleString("id-ID");
  return v == null ? "" : String(v);
}

function openForm(row: MasterRow | null) {
  editing.value = row;
  form.value = Object.fromEntries(
    formFields.value.map((f) => [f.key, row ? row[f.key] : (f.default ?? (f.type === "boolean" ? false : null))]),
  );
  formOpen.value = true;
}

function clean(field: CrudField, value: unknown) {
  if (field.type === "boolean") return value === true;
  if (field.type === "images") return Array.isArray(value) ? value : [];
  if (value == null || value === "") return null;
  if (field.type === "number" || field.type === "money") return Number(value);
  if (field.type === "select") return field.options?.find((o) => String(o.value) === String(value))?.value ?? null;
  const text = field.upper ? String(value).trim().toUpperCase() : String(value).trim();
  return field.transform ? field.transform(text) : text;
}

async function upload(field: CrudField, e: Event) {
  const input = e.target as HTMLInputElement;
  const files = [...(input.files ?? [])];
  if (!files.length || !field.bucket) return;
  uploading.value = true;
  try {
    for (const file of files) {
      const ext = file.name.split(".").pop()?.toLowerCase() || "png";
      const path = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
      const { error } = await supabase.storage.from(field.bucket).upload(path, file, { contentType: file.type });
      if (error) throw error;
      const url = supabase.storage.from(field.bucket).getPublicUrl(path).data.publicUrl;
      if (field.type === "images") form.value[field.key] = [...((form.value[field.key] as string[] | null) ?? []), url];
      else form.value[field.key] = url;
    }
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    uploading.value = false;
    input.value = "";
  }
}

async function submit() {
  const values: Record<string, unknown> = editing.value ? {} : { ...props.insertDefaults, ...props.filter };
  for (const f of formFields.value) {
    if (editing.value && f.lockOnEdit) continue;
    values[f.key] = clean(f, form.value[f.key]);
  }
  try {
    await save.mutateAsync({ id: editing.value?.id, values });
    formOpen.value = false;
    toast.success(t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
  }
}

async function confirmDelete() {
  if (!deleting.value) return;
  try {
    await remove.mutateAsync(deleting.value.id);
    deleting.value = null;
  } catch (err) {
    toast.error(serverError(err));
  }
}

type SelectValue = string | number | null;
type MoneyValue = number | null;
const inputClass = FIELD_CLASS;
</script>

<template>
  <section class="space-y-3">
    <div class="toolbar">
      <h2 class="mr-auto font-semibold">{{ title }}</h2>
      <AppSelect
        v-for="f in filterFields"
        :key="f.key"
        :model-value="filters[f.key] ?? null"
        :options="filterOptions(f)"
        :null-label="`${f.label}: ${t('common.all')}`"
        class="w-40"
        :aria-label="f.label"
        @update:model-value="filters = { ...filters, [f.key]: $event }"
      />
      <Input
        v-model="search"
        type="search"
        class="h-9 w-48"
        :placeholder="t('common.search')"
        :aria-label="t('common.search')"
      />
      <div v-if="grid" role="radiogroup" :aria-label="t('common.view')" class="bg-card flex h-9 items-center gap-0.5 rounded-md border p-0.5">
        <Button
          v-for="v in [{ key: 'table', icon: Rows3 }, { key: 'grid', icon: LayoutGrid }] as const"
          :key="v.key"
          role="radio"
          :aria-checked="view === v.key"
          :variant="view === v.key ? 'soft' : 'ghost'"
          size="icon"
          class="size-7 border-0 shadow-none"
          :tooltip="t(`common.views.${v.key}`)"
          @click="view = v.key"
        >
          <component :is="v.icon" />
        </Button>
      </div>
      <Button v-if="!readonly && can(feature, 'create')" size="sm" @click="openForm(null)">
        <Plus /> {{ t("common.add") }}
      </Button>
    </div>

    <LoadingState v-if="rows.isPending.value" :variant="showGrid ? 'grid' : 'table'" :columns="tableFields.length + 1" />
    <EmptyState v-else-if="rows.isError.value" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="rows.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <EmptyState v-else-if="!visible.length" :title="t('common.empty')" />
    <div v-else-if="showGrid" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-5">
      <article v-for="row in paged.rows.value" :key="row.id" class="bg-card group flex flex-col overflow-hidden rounded-xl border transition-colors hover:border-primary/60">
        <div class="bg-secondary/50 relative flex aspect-[4/3] items-center justify-center">
          <img v-if="imageOf(row)" :src="imageOf(row)!" alt="" class="size-full object-cover" @error="markBroken(row.id)" />
          <component :is="placeholder ?? Package" v-else class="size-10 text-stone-300" :stroke-width="1" />
          <StatusBadge v-if="'is_active' in row && !row.is_active" tone="muted" class="absolute top-2 left-2">{{ t("common.inactive") }}</StatusBadge>
        </div>
        <div class="flex flex-1 flex-col gap-1 p-3">
          <p class="line-clamp-2 text-sm font-semibold">{{ row[grid!.title] }}</p>
          <p class="text-muted-foreground truncate text-xs">
            {{ (grid!.subtitle ?? []).map((k) => display(fields.find((f) => f.key === k) ?? { key: k, label: k }, row)).filter(Boolean).join(" · ") }}
          </p>
          <div class="mt-auto flex justify-end gap-1 pt-2">
            <slot name="row-actions" :row="row" />
            <Button v-if="!readonly && !appendOnly && can(feature, 'update')" variant="ghost" size="icon" class="size-8" :tooltip="t('common.edit')" @click="openForm(row)">
              <Pencil />
            </Button>
            <Button v-if="!readonly && !appendOnly && can(feature, 'delete')" variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.delete')" @click="deleting = row">
              <Trash2 />
            </Button>
          </div>
        </div>
      </article>
    </div>
    <div v-else class="bg-card overflow-x-auto rounded-xl border">
      <table v-stack class="w-full text-sm">
        <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
          <tr>
            <th
              v-for="f in tableFields"
              :key="f.key"
              class="px-3 py-2 font-medium whitespace-nowrap"
              :class="{ 'text-right': f.type === 'number' || f.type === 'money', 'w-px': f.type === 'number' || f.type === 'money' || f.type === 'boolean' || f.type === 'image' }"
            >
              {{ f.label }}
            </th>
            <th class="w-px px-3 py-2"><span class="sr-only">{{ t("common.actions") }}</span></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in paged.rows.value" :key="row.id" class="border-b last:border-0">
            <td
              v-for="f in tableFields"
              :key="f.key"
              class="px-3 py-2"
              :class="{
                'font-mono text-xs': f.mono,
                'text-right tabular-nums': f.type === 'number' || f.type === 'money',
                'w-px whitespace-nowrap': f.type === 'number' || f.type === 'money' || f.type === 'boolean' || f.type === 'image',
              }"
            >
              <StatusBadge v-if="f.type === 'boolean'" :tone="row[f.key] ? 'success' : 'muted'">
                {{ row[f.key] ? t("common.yes") : t("common.no") }}
              </StatusBadge>
              <template v-else-if="f.type === 'image'">
                <img
                  v-if="row[f.key] && !brokenImg.has(row.id)"
                  :src="String(row[f.key])"
                  alt=""
                  class="h-10 w-auto max-w-28 rounded-md border object-contain"
                  @error="markBroken(row.id)"
                />
                <ImageOff v-else class="text-muted-foreground size-4" />
              </template>
              <div v-else-if="grid?.image && f.key === grid.title" class="flex items-center gap-2">
                <img v-if="imageOf(row)" :src="imageOf(row)!" alt="" class="size-8 shrink-0 rounded-md border object-cover" @error="markBroken(row.id)" />
                <span v-else class="bg-secondary flex size-8 shrink-0 items-center justify-center rounded-md"><component :is="placeholder ?? Package" class="size-4 text-stone-400" /></span>
                <span>{{ display(f, row) }}</span>
              </div>
              <template v-else>{{ display(f, row) }}</template>
            </td>
            <td class="px-3 py-1.5">
              <div class="flex justify-end gap-1">
                <slot name="row-actions" :row="row" />
                <Button
                  v-if="!readonly && !appendOnly && can(feature, 'update')"
                  variant="ghost"
                  size="icon"
                  class="size-8"
                  :tooltip="t('common.edit')"
                  @click="openForm(row)"
                >
                  <Pencil />
                </Button>
                <Button
                  v-if="!readonly && !appendOnly && can(feature, 'delete')"
                  variant="ghost-destructive"
                  size="icon"
                  class="size-8"
                  :tooltip="t('common.delete')"
                  @click="deleting = row"
                >
                  <Trash2 />
                </Button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <TablePager
      v-if="!rows.isPending.value && visible.length"
      v-model:page="paged.page.value"
      v-model:per-page="paged.perPage.value"
      :total="paged.total.value"
      :pages="paged.pages.value"
    />

    <Dialog v-model:open="formOpen">
      <DialogContent :class="wide ? 'sm:max-w-3xl' : 'sm:max-w-lg'">
        <DialogHeader>
          <DialogTitle>{{ title }}</DialogTitle>
        </DialogHeader>
        <form
          :id="`crud-${table}`"
          :class="['max-h-[70vh] overflow-y-auto p-1', wide ? 'grid gap-x-4 gap-y-3 sm:grid-cols-2' : 'space-y-3']"
          @submit.prevent="submit"
        >
          <div v-for="f in formFields" :key="f.key" :class="['space-y-1.5', wide && fullRow(f) && 'sm:col-span-2']">
            <label v-if="f.type === 'boolean'" class="flex items-center gap-2 text-sm">
              <input v-model="form[f.key]" type="checkbox" class="accent-primary size-4" />
              {{ f.label }}
            </label>
            <template v-else>
              <Label :for="`crud-${table}-${f.key}`">{{ f.label }}</Label>
              <AppSelect
                v-if="f.type === 'select'"
                :id="`crud-${table}-${f.key}`"
                :model-value="form[f.key] as SelectValue"
                :options="f.options ?? []"
                :null-label="f.required ? undefined : '-'"
                :required="f.required"
                :disabled="!!editing && f.lockOnEdit"
                @update:model-value="form[f.key] = $event"
              />
              <div v-else-if="f.type === 'image'" class="flex items-center gap-3">
                <img v-if="form[f.key]" :src="String(form[f.key])" alt="" class="h-14 w-auto max-w-36 shrink-0 rounded-md border object-contain" />
                <input
                  :id="`crud-${table}-${f.key}`"
                  type="file"
                  accept="image/png,image/jpeg,image/webp"
                  class="file:bg-secondary file:text-foreground min-w-0 flex-1 text-xs file:mr-3 file:rounded-md file:border-0 file:px-3 file:py-1.5 file:text-xs file:font-medium"
                  :disabled="uploading"
                  @change="upload(f, $event)"
                />
                <Button v-if="form[f.key]" type="button" variant="ghost" size="icon" class="size-8" :tooltip="t('common.delete')" @click="form[f.key] = null"><X /></Button>
              </div>
              <div v-else-if="f.type === 'images'" class="space-y-2">
                <div v-if="(form[f.key] as string[] | null)?.length" class="flex flex-wrap gap-2">
                  <div v-for="(url, i) in form[f.key] as string[]" :key="url" class="relative">
                    <img :src="url" alt="" class="size-16 rounded-md border object-cover" />
                    <button
                      type="button"
                      class="bg-background absolute -top-1.5 -right-1.5 rounded-full border p-0.5"
                      :aria-label="t('common.delete')"
                      @click="form[f.key] = (form[f.key] as string[]).filter((_, j) => j !== i)"
                    >
                      <X class="size-3" />
                    </button>
                  </div>
                </div>
                <input
                  :id="`crud-${table}-${f.key}`"
                  type="file"
                  multiple
                  accept="image/png,image/jpeg,image/webp"
                  class="file:bg-secondary file:text-foreground w-full text-xs file:mr-3 file:rounded-md file:border-0 file:px-3 file:py-1.5 file:text-xs file:font-medium"
                  :disabled="uploading"
                  @change="upload(f, $event)"
                />
              </div>
              <MoneyInput
                v-else-if="f.type === 'money'"
                :id="`crud-${table}-${f.key}`"
                :model-value="form[f.key] as MoneyValue"
                :required="f.required"
                :disabled="!!editing && f.lockOnEdit"
                @update:model-value="form[f.key] = $event"
              />
              <textarea
                v-else-if="f.type === 'textarea'"
                :id="`crud-${table}-${f.key}`"
                v-model="form[f.key] as string"
                :class="[inputClass, 'h-20 py-2']"
                :required="f.required"
              />
              <input
                v-else
                :id="`crud-${table}-${f.key}`"
                v-model="form[f.key]"
                :type="f.type === 'number' || f.type === 'date' || f.type === 'time' ? f.type : 'text'"
                :step="f.step ?? 'any'"
                :min="f.type === 'number' ? 0 : undefined"
                :pattern="f.pattern"
                :class="[inputClass, { uppercase: f.upper, 'font-mono': f.mono }]"
                :required="f.required"
                :disabled="!!editing && f.lockOnEdit"
              />
            </template>
            <p v-if="f.hint" class="text-muted-foreground text-xs">{{ f.hint }}</p>
          </div>
        </form>
        <DialogFooter>
          <Button variant="outline" @click="formOpen = false">{{ t("common.cancel") }}</Button>
          <Button type="submit" :form="`crud-${table}`" :disabled="save.isPending.value || uploading" :loading="save.isPending.value || uploading"><Save /> {{ t("common.save") }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <ConfirmDialog
      :open="!!deleting"
      :title="t('common.deleteTitle')"
      :description="t('common.deleteBody')"
      :confirm-label="t('common.delete')"
      :busy="remove.isPending.value"
      destructive
      @update:open="deleting = null"
      @confirm="confirmDelete"
    />
  </section>
</template>
