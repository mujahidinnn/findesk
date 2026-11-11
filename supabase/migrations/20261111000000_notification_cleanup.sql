-- A user may delete their own notifications (the bell's "clear read"); nothing else about the table changes.
CREATE POLICY notifications_delete_own ON public.t_notifications FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));
GRANT DELETE ON public.t_notifications TO authenticated;
