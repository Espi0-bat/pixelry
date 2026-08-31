-- FK: deliveries.client_id → profiles.id
ALTER TABLE public.deliveries
  ADD CONSTRAINT deliveries_client_id_profiles_fkey
  FOREIGN KEY (client_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- FK: portal_events.client_id → profiles.id
ALTER TABLE public.portal_events
  ADD CONSTRAINT portal_events_client_id_profiles_fkey
  FOREIGN KEY (client_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- FK: messages.client_id → profiles.id (para joins futuros)
ALTER TABLE public.messages
  ADD CONSTRAINT messages_client_id_profiles_fkey
  FOREIGN KEY (client_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
