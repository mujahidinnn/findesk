
CREATE POLICY attachments_update ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'attachments' AND owner = (SELECT auth.uid()))
  WITH CHECK (bucket_id = 'attachments' AND owner = (SELECT auth.uid()));
CREATE POLICY attachments_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'attachments' AND owner = (SELECT auth.uid()));

DROP POLICY IF EXISTS attachments_read ON storage.objects;
CREATE POLICY attachments_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'attachments' AND (SELECT public.has_any_access())
         AND (name NOT LIKE 'expense/%'
              OR owner = (SELECT auth.uid())
              OR EXISTS (SELECT 1 FROM public.t_expense_claim_lines l WHERE l.receipt_path = name)));
