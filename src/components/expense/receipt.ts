import { supabase } from "@/integrations/supabase/client";

export async function openReceipt(path: string) {
  const tab = window.open("", "_blank");
  const { data, error } = await supabase.storage.from("attachments").createSignedUrl(path, 60);
  if (error || !data) {
    tab?.close();
    throw error;
  }
  if (tab) tab.location.href = data.signedUrl;
  else window.location.assign(data.signedUrl);
}
