-- S2 — Limite de tamanho nos buckets de arquivos.
--
-- client-uploads e deliveries não tinham file_size_limit: qualquer conta
-- autenticada (e o cadastro público estava aberto) podia subir arquivos do
-- tamanho máximo do projeto, sem teto por bucket, até esgotar a cota de
-- Storage.
--
-- 50 MB por arquivo, igual ao teto do plano gratuito. Se o limite global do
-- projeto subir um dia, este continua valendo aqui.
--
-- allowed_mime_types NÃO foi definido de propósito: o tipo é declarado pelo
-- próprio cliente no upload, então não protege contra abuso, e clientes de
-- agência mandam .psd/.ai/.mov com tipos imprevisíveis. Não vale a quebra.

update storage.buckets
set file_size_limit = 52428800  -- 50 MB
where id in ('client-uploads', 'deliveries')
  and (file_size_limit is null or file_size_limit > 52428800);
