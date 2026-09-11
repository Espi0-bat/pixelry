-- Tabela de mensagens da Central de Atendimento
CREATE TABLE public.messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id   uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  content     text NOT NULL,
  from_client boolean NOT NULL DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cliente_gerencia_suas_mensagens"
  ON public.messages FOR ALL
  USING (client_id = auth.uid())
  WITH CHECK (client_id = auth.uid());

-- Buckets de Storage
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES
  ('pixelry-assets',  'pixelry-assets',  true,  52428800),
  ('client-uploads',  'client-uploads',  false, 52428800)
ON CONFLICT (id) DO NOTHING;

-- RLS para client-uploads: cliente só acessa seus próprios arquivos
CREATE POLICY "cliente_upload_proprios_arquivos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'client-uploads' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "cliente_le_proprios_arquivos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'client-uploads' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- RLS para pixelry-assets: leitura pública
CREATE POLICY "assets_leitura_publica"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'pixelry-assets');
