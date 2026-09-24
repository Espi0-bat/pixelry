# Auditoria do Supabase da PIXELRY — 24/09/2026

Projeto: `Pixelry Portal` (`bbxpbdgpxpbqwpmewvld`, sa-east-1, Postgres 17.6).
Escopo: banco (RLS, grants, funções, triggers, índices), Storage, Edge Functions, Auth e o que o front expõe.
Método: leitura do repo + consultas ao banco de produção via CLI (`supabase db query --linked`) + testes de permissão executados **sob o papel real** (`set local role anon/authenticated` + claims JWT) dentro de transações com `rollback`. Durante o diagnóstico nada foi alterado; as correções entraram depois, por migration (seção 5).

Seções 1 a 4: diagnóstico e plano como escritos antes de agir. Seção 5: o que foi aplicado em produção em 24/09, como foi verificado, e o que ainda falta (dashboard e front).

---

## 1. Resumo executivo

| # | Achado | Gravidade | Status |
|---|--------|-----------|--------|
| E1 | Admin não consegue mudar status de entrega (tela Status): `permission denied for table deliveries` | **Bug em produção** | Confirmado por teste |
| E2 | Mensagens e arquivos internos: destinatário não consegue marcar como lido (RLS bloqueia) | Bug em produção | Confirmado por teste |
| E3 | Histórico de migrations divergente entre repo e produção (`db push` vai quebrar) | Risco operacional | Confirmado |
| S1 | `INSERT` anônimo direto em `leads` continua aberto: bypass de honeypot, rate limit e validação | **Alta** | Confirmado por teste |
| S2 | Cadastro público de conta está **habilitado** e a conta nasce como `client` | **Alta** | Confirmado por probe |
| S3 | `newsletter_subscribers`: insert público sem limite, sem validação, sem uso no front | Média | Confirmado por teste |
| S4 | E-mails Gmail dos sócios expostos no bundle JS e legíveis por qualquer cliente logado; sem MFA; proteção de senha vazada desligada | Média | Confirmado |
| S5 | Cota de e-mail do Auth pode ser esgotada por terceiros (se SMTP built-in) | Média | A verificar no dashboard |
| S6 | 4 funções `SECURITY DEFINER` chamáveis por `anon` via RPC (advisor 0028/0029) | Baixa | Confirmado (advisors) |
| S7 | Grants excessivos para `anon`/`authenticated` (inclusive `TRUNCATE`) em todas as tabelas | Baixa | Confirmado |
| S8 | Policies duplicadas/obsoletas e 18 avisos de performance de RLS (`auth_rls_initplan`) | Baixa | Confirmado (advisors) |

O que **está bem** e não precisa de ação: webhook do Mercado Pago falha fechado (401 sem assinatura, janela de 5 min, idempotência em 3 camadas); `sync-notion` devolve 401 sem token; o rate limit por IP do `submit-lead` **não é falsificável** via `X-Forwarded-For` (testei com IP forjado e o bucket gravou meu IP real); buckets de arquivos de cliente são privados com URL assinada; `profiles.role` está protegido por grant de coluna + trigger; escalação de privilégio por `role` está fechada; `.env` está fora do git; segredos (MP, Resend, Notion) só existem nos Secrets/Vault.

---

## 2. Erros em produção (o que está quebrado hoje)

### E1 — Admin não consegue atualizar entregas

**Sintoma:** na tela Status do painel, mudar status de uma entrega não faz nada (o erro é engolido pelo front).

**Causa:** o papel `authenticated` tem `UPDATE` em `deliveries` **só na coluna `status`** (grant por coluna). O front em [Status.jsx:102](../src/admin/pages/Status.jsx#L102) envia `status` **e** `updated_at`. Reproduzi como `super_admin`:

```
ERROR: 42501: permission denied for table deliveries
HINT: GRANT UPDATE ON public.deliveries TO authenticated;
```

Esse grant por coluna **não está em nenhuma migration** (nem local, nem nas 9 remotas). Foi feito à mão. O portal do cliente não sofre porque [ClientPortal.jsx:2459](../src/pages/ClientPortal.jsx#L2459) envia só `status`.

**Correção proposta (banco, sem deploy de front):**
```sql
grant update (status, updated_at) on public.deliveries to authenticated;
revoke update on public.deliveries from anon;  -- anon tem UPDATE total e não precisa
```
Alternativa mais limpa a médio prazo: trigger `set updated_at = now()` e tirar o campo do front.

### E2 — "Marcar como lido" em mensagens/arquivos internos falha

**Causa:** `users_see_own_messages` (e `users_see_own_files`) é `FOR ALL` com `WITH CHECK (from_id = auth.uid())`. O destinatário passa no `USING` (`to_id = uid`) mas o `UPDATE` de `read_at` falha no `WITH CHECK` porque ele não é o remetente. Reproduzi com uma linha semeada e rollback:

```
ERROR: 42501: new row violates row-level security policy for table "internal_messages"
```

O front em [InternalMessages.jsx:47](../src/admin/pages/InternalMessages.jsx#L47) e [InternalFiles.jsx:42](../src/admin/pages/InternalFiles.jsx#L42) ignora o erro, então o contador de não lidas nunca zera de verdade.

**Correção proposta:** separar a policy em SELECT / INSERT / UPDATE, com `UPDATE ... using (to_id = uid) with check (to_id = uid)`, ou, no mínimo, `with check (from_id = uid or to_id = uid)`.

### E3 — Migrations divergentes

`supabase migration list` mostra:
- 9 arquivos locais `20260902*` que **não constam** no histórico remoto (foram aplicados via MCP e registrados com outro timestamp).
- 9 versões remotas `20260903175048`..`20260903175521` que **não existem** no repo, incluindo `harden_helper_fn_execute` e o `revert_harden_helper_fn_execute` do incidente de 02/09.
- O arquivo `20260902000800_leads_insert_service_role_only` (corte do insert anônimo) **não foi aplicado** em produção (ver S1).
- O grant por coluna de E1 não tem migration.

Hoje um `supabase db push` tentaria reaplicar os 9 arquivos locais (vários falhariam em `add constraint` duplicada) e o repo não reflete o estado real.

**Correção proposta:** `supabase migration repair` marcando os `20260902*` como `reverted` e os `20260903*` como `applied`; renomear os arquivos locais para as versões remotas; criar arquivos para o revert e para o grant de E1; então aplicar o corte de leads como migration nova.

---

## 3. Vetores de invasão e de derrubada

### S1 — Insert anônimo em `leads` continua aberto (Alta)

A policy `allow_insert_leads` (`with_check true`, papel `public`) ainda existe em produção e `anon` tem `INSERT` na tabela. Testei como `anon` sem RETURNING: **inseriu**. Ou seja, qualquer um pode fazer `POST /rest/v1/leads` com a anon key (que é pública no bundle) e pular honeypot, rate limit por IP (5/min, 30/h) e validação da Edge Function.

O que ainda segura: constraints de tamanho/formato e o trigger `leads_flood_guard` (30 leads/min **global**). Isso abre um DoS barato: um script que mantém 30 inserts/min com a anon key **bloqueia todos os leads reais** do site, porque o trigger não distingue origem. E a tela Leads do painel fica lotada de lixo.

Pré-requisitos do corte já estão cumpridos: `submit-lead` está deployada (v1, 03/09) e [LeadCaptureModal.jsx:101](../src/components/LeadCaptureModal.jsx#L101) já chama a função. Não há mais nenhum `from('leads').insert` no front.

**Correção:** aplicar o `PASSO_2` que já está no repo (`drop policy allow_insert_leads`) mais `revoke insert on public.leads from anon, authenticated` (o insert agora é só `service_role`). Adicionar índice em `leads(created_at)` para o trigger de flood não fazer seq scan quando a tabela crescer.

### S2 — Cadastro público habilitado e conta vira `client` (Alta)

Probe não destrutivo em `/auth/v1/signup` (senha forte + e-mail inválido) devolveu `validation_failed: invalid format`, o que só acontece **depois** das checagens `DisableSignup` e `Email.Enabled`. Logo, qualquer pessoa cria conta com a anon key. O trigger `handle_new_user` cria o perfil e o default da coluna faz a conta nascer com `role = 'client'`.

Simulei uma conta nova (em transação com rollback). Ela consegue:
- **Ler os 5 perfis** da empresa via policy `team_members_see_each_other`: nomes, e-mails e `contact_info` de super_admins, manager e employee.
- **Inserir em `messages`** com o próprio `client_id`: aparece como "novo cliente" na Central de Atendimento ([Suporte.jsx](../src/admin/pages/Suporte.jsx)) via Realtime. Spam direto no inbox da equipe.
- **Inserir em `portal_events`** sem limite.
- **Subir arquivos em `client-uploads`** na própria pasta. O bucket **não tem `file_size_limit` nem `allowed_mime_types`** (`deliveries` também não). Nada impede encher a cota de Storage do projeto: custo ou indisponibilidade.
- Chamar Edge Functions autenticado (todas devolvem 403 por papel; ok).

Não consegue ler leads, entregas, faturas, metas, kanban ou notas de outros. RLS está correta nisso.

**Correção:**
1. Dashboard → Auth → Providers → Email: **desligar "Allow new users to sign up"**. Clientes já são criados por convite via `create-client`; funcionários via `create-employee`. Nada no front usa `signUp`.
2. `update storage.buckets set file_size_limit = 52428800` em `client-uploads` e `deliveries`, e `allowed_mime_types` em `client-uploads` (pdf, imagens, zip, docx, xlsx).
3. Trocar `team_members_see_each_other` para exigir `is_team()` do lado de quem lê (cliente não precisa ver a equipe).
4. Trigger ou constraint que limite `messages`/`portal_events` por cliente por minuto (defesa em profundidade, mesmo com signup fechado).

### S3 — `newsletter_subscribers` aberta (Média)

Policy `Permitir inserções públicas no formulário` (`with_check true`, papel `public`). Sem constraint de tamanho/formato (só `unique(email)`), sem rate limit, sem trigger. Testei como `anon`: **inseriu**. A tabela não está em nenhuma migration e **nenhum arquivo do front a usa**. É uma porta de flood sem propósito.

**Correção:** `drop policy` + `revoke insert from anon, authenticated`. Se a newsletter voltar, entrar pelo mesmo padrão do `submit-lead`.

### S4 — Identidade da equipe exposta e sem segunda camada (Média)

- [config/supabase.js](../src/config/supabase.js) embute como default os Gmails pessoais dos dois super_admins e da manager. Vai para o bundle público do GitHub Pages. Somado a S2, qualquer um sabe exatamente quais contas atacar em `/auth/v1/token` (limite default: 30 tentativas/5 min por IP, e IP é barato).
- Advisor: **proteção contra senha vazada (HaveIBeenPwned) desligada**.
- Não há MFA para a equipe.
- A alertagem de admin no login é só no cliente (`isAdminEmail`); a segurança real é a RLS por `role`, o que está certo, mas os e-mails no bundle não precisam existir.

**Correção:** ligar leaked password protection; exigir MFA (TOTP) para `super_admin`/`manager`; tirar os e-mails default do bundle e decidir "é admin?" pelo `profiles.role` (já disponível após login); avaliar contas `@pixelry.com.br` em vez de Gmail pessoal.

### S5 — Cota de e-mail do Auth (Média, a verificar)

`resetPasswordForEmail` e `inviteUserByEmail` dependem do SMTP do Auth. Se o projeto ainda usa o SMTP built-in, o limite é **2 e-mails/hora no projeto inteiro**: um terceiro pedindo reset para qualquer e-mail (o endpoint não revela se existe) esgota a cota e derruba convites e recuperações legítimas. Não consegui ler as configurações de Auth pela CLI.

**Verificar no dashboard:** Auth → SMTP (custom via Resend, que já está contratado?) e Auth → Rate Limits. Ligar CAPTCHA (Turnstile) no reset de senha e no login.

### S6 — Funções `SECURITY DEFINER` expostas via RPC (Baixa)

Advisors 0028/0029: `is_admin()`, `is_team()`, `deliveries_client_update_guard()`, `leads_flood_guard()` são chamáveis por `anon`/`authenticated` em `/rest/v1/rpc/...`.

- `is_admin`/`is_team`: devolvem só `true/false` sobre o próprio chamador. Risco real é nulo. **Não revogar**: o incidente de 02/09 provou que policy exige EXECUTE do papel que consulta. O único caminho que fecha o advisor é mover as duas para um schema fora da API (ex.: `private`) e reescrever as policies para `private.is_admin()`. Vale fazer, mas com o teste replicando a migration byte a byte (lição registrada em memória).
- As duas funções de trigger: revogar é seguro (PostgREST nem consegue chamar função que retorna `trigger`). `revoke execute ... from anon, authenticated, public`.

### S7 — Grants excessivos (Baixa)

`anon` tem `DELETE, INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER` em **todas** as tabelas (default do Supabase). RLS barra DML, mas `TRUNCATE` não passa por RLS (só não é alcançável via PostgREST). Após S1 e S3, `anon` não precisa de nada além de `SELECT` em nenhuma tabela; `authenticated` nunca precisa de `TRUNCATE`/`TRIGGER`/`REFERENCES`. Reduzir superfície e o número de policies "para o caso de".

### S8 — Higiene de policies e performance de RLS (Baixa)

- `invoices.service_role_full_access` usa `auth.role() = 'service_role'` (deprecado e inútil: service_role ignora RLS). Remover.
- `kanban_tasks` tem duas policies idênticas (`Staff full access` e `admin_only_kanban`). Manter uma.
- 18 policies reavaliam `auth.uid()` por linha. Trocar por `(select auth.uid())`. Irrelevante com 5 usuários, mas é mecânico e barato.
- `deliveries` e `profiles` têm policies duplicadas para SELECT (`Admin full access` + específica). Aceitável, mas gera os 16 avisos `multiple_permissive_policies`.

### Sobre "lançar muitas requisições para derrubar"

Onde um atacante gasta pouco e custa caro para vocês, em ordem:
1. `POST /rest/v1/leads` (S1): lock-out dos leads reais e lixo no painel.
2. Signup + upload em `client-uploads` (S2): cota de Storage.
3. `POST /rest/v1/newsletter_subscribers` (S3): crescimento do banco (hoje 13 MB).
4. Reset de senha em massa (S5): cota de e-mail.
5. Invocações de Edge Function: `submit-lead` sem auth passa por honeypot e rate limit, mas cada chamada conta na cota de invocações. Sem WAF na frente do `*.supabase.co` não há como bloquear na borda; CAPTCHA no formulário é a mitigação prática.

Realtime só publica `kanban_tasks` (com RLS). Índices cobrem as chaves usadas nas policies. Nenhuma query lenta relevante no `pg_stat_statements` (o único item pesado é a recarga de schema do PostgREST, normal).

---

## 4. Plano de execução

Regra para todo SQL: rodar primeiro em `begin … rollback` sob `set local role authenticated/anon` **copiando o SQL da migration**, não reescrevendo. Depois aplicar via migration e registrar no histórico.

### Fase 0 — hoje, só banco e dashboard, sem deploy de front

| Ordem | Ação | Achado | Teste de aceite |
|-------|------|--------|-----------------|
| 1 | `grant update (status, updated_at) on deliveries to authenticated; revoke update on deliveries from anon` | E1 | Como super_admin: `update deliveries set status=status, updated_at=now()` passa. Como cliente: só `status` passa; `title` cai no trigger. |
| 2 | `drop policy allow_insert_leads; revoke insert on leads from anon, authenticated` | S1 | Como anon: insert falha com 42501. `submit-lead` real grava. |
| 3 | `drop policy "Permitir inserções públicas no formulário"; revoke insert on newsletter_subscribers from anon, authenticated` | S3 | Como anon: insert falha. |
| 4 | Dashboard → Auth → desligar signup por e-mail | S2 | Probe `POST /auth/v1/signup` devolve `signup_disabled`. |
| 5 | `file_size_limit` + `allowed_mime_types` em `client-uploads` e `deliveries` | S2 | Upload de 60 MB falha; PDF de 5 MB passa. |
| 6 | Reescrever policies de `internal_messages`/`internal_files` (UPDATE por destinatário) | E2 | Como employee destinatário: `update read_at` passa. |
| 7 | Dashboard → Auth → ligar leaked password protection | S4 | Advisor some. |

### Fase 1 — esta semana

| Ordem | Ação | Achado |
|-------|------|--------|
| 8 | `supabase migration repair` + trazer os 9 arquivos remotos para o repo + migration para o grant de E1 | E3 |
| 9 | `team_members_see_each_other` → exigir `is_team()` do lado do leitor | S2 |
| 10 | Verificar SMTP custom e rate limits do Auth; ligar Turnstile em login/reset e no `submit-lead` (validar token na função) | S5 |
| 11 | MFA TOTP obrigatório para `super_admin`/`manager` (App: checar `aal2` no AdminLayout) | S4 |
| 12 | Tirar e-mails default de [config/supabase.js](../src/config/supabase.js); decidir admin pelo `profiles.role` | S4 |
| 13 | `create index on leads (created_at)`; trigger de limite por cliente em `messages`/`portal_events` | S1, S2 |

### Fase 2 — higiene

| Ordem | Ação | Achado |
|-------|------|--------|
| 14 | Revogar EXECUTE das 2 funções de trigger; mover `is_admin`/`is_team` para schema `private` e reapontar policies (com teste byte a byte) | S6 |
| 15 | Revogar de `anon` tudo exceto SELECT; revogar `TRUNCATE/TRIGGER/REFERENCES` de `authenticated` | S7 |
| 16 | Remover `service_role_full_access` e a policy duplicada de kanban; `(select auth.uid())` nas 18 policies | S8 |
| 17 | `create-invoice`: não devolver `detail: errBody` do Mercado Pago nem `err.message` ao cliente | — |
| 18 | Trigger `updated_at` em `deliveries` e tirar o campo do front | E1 |

---

## 5. Execução em 24/09/2026 — aplicado

**As 7 migrations estão em produção** (`db push` rodado pelo Ezer às ~03:55 UTC de 24/09; o `migration repair` e os testes pelo Claude Code). Histórico local e remoto alinhados: 43/43, nenhuma pendente, nenhuma só no remoto.

O que foi feito:

1. **Histórico de migrations alinhado com o remoto (E3).** Os 8 arquivos `20260902*` já aplicados foram renomeados para as versões que constam no histórico remoto (`20260903175048` … `20260903175434`); os 2 que só existiam no remoto (`harden_helper_fn_execute` e seu `revert`) foram trazidos com o SQL exato que rodou; `20260902_fix_profile_role_escalation` virou `20260902000050_…` (está aplicada em produção, só falta registrar). `PASSO_2_corte_leads.sql` foi removido: virou migration de verdade.
2. **7 migrations novas**, cada uma testada em produção **sob os papéis reais** (`set local role` + claims JWT) dentro de `begin … rollback`, copiando o SQL do arquivo, não reescrito:

| Migration | Cobre | Testes que passaram |
|-----------|-------|---------------------|
| `20260924033535_fix_deliveries_update_grant` | E1 | admin atualiza `status`+`updated_at` ✔; cliente atualiza só `status` da própria ✔; cliente tenta `title` → `permission denied` ✔; anon → `permission denied` ✔ |
| `20260924033536_leads_insert_service_role_only` | S1 | service_role insere ✔; anon → `permission denied for table leads` ✔; cliente logado → `permission denied` ✔; admin continua lendo ✔; índice `idx_leads_created_at` criado ✔ |
| `20260924033537_newsletter_close` | S3 | anon e authenticated → `permission denied` ✔ |
| `20260924033538_storage_bucket_limits` | S2 | `client-uploads` e `deliveries` ficam com 50 MB; os outros não mudam ✔ |
| `20260924033539_internal_read_receipts` | E2 | employee (destinatário) marca mensagem e arquivo como lidos ✔ e responde ✔; admin (remetente) enxerga as duas ✔; destinatário tenta editar `content` → `permission denied` (grant só em `read_at`) ✔; cliente tenta inserir → RLS ✔; cliente lê 0 ✔; remetente marcando a própria → 0 linhas, sem erro ✔ |
| `20260924033540_profiles_team_visibility` | S2 | cliente vê 1 (o próprio) ✔; employee vê 4 (equipe) ✔; admin vê 5 ✔; anon vê 0 ✔; cliente ainda edita o próprio perfil ✔ |
| `20260924033541_client_write_flood_guard` | S2 / item 13 | cliente manda 30 mensagens e 60 eventos ✔, admin responde em seguida ✔; 31ª mensagem → `53400 rate limited` ✔; 61º evento → `53400` ✔; anon chama a função via RPC → `permission denied for function` ✔; índice `idx_messages_client_id_created_at` ✔ |

**Desvios em relação ao plano da seção 4, com o motivo:**
- `allowed_mime_types` **não** foi definido nos buckets: o tipo é declarado pelo próprio cliente no upload, então não impede abuso, e clientes de agência mandam `.psd/.ai/.mov` com tipos imprevisíveis. Só o limite de 50 MB entrou.
- A trava de flood **isenta a equipe** (`is_team()`), senão a resposta do admin a um cliente que floodou ficava bloqueada junto. No primeiro teste foi exatamente isso que aconteceu.
- Em `leads` revoguei também `SELECT` do `anon` e `INSERT` do `authenticated`, além do que o PASSO_2 previa. Nenhuma tela usa esses caminhos.
- `is_admin()`/`is_team()` seguem executáveis por `anon` (advisor 0028): mover para schema privado ficou para a Fase 2, como planejado.

### Verificação depois do push (estado real, testes com rollback)

| Checagem | Resultado |
|----------|-----------|
| Admin muda `status`+`updated_at` de entrega (E1) | ✔ passa |
| Employee destinatário marca mensagem interna como lida (E2) | ✔ passa |
| Cliente logado conta perfis visíveis (S2) | ✔ 1, só o próprio |
| 31ª mensagem do cliente no mesmo minuto | ✔ `53400 rate limited` |
| `POST /rest/v1/leads` com a anon key, pela REST de verdade (S1) | ✔ `HTTP 401` `permission denied for table leads` |
| `POST /rest/v1/newsletter_subscribers` com a anon key (S3) | ✔ `HTTP 401` `permission denied` |
| Lead real pelo `submit-lead` (ponta a ponta, como o site faz) | ✔ gravou; a linha de teste (`audit-e2e@example.com`) foi apagada em seguida |
| Grants por coluna | `deliveries`: `status,updated_at`; `internal_messages`/`internal_files`: `read_at` |
| Buckets | `client-uploads` e `deliveries` com 50 MB |
| Triggers e índices novos | `messages_flood_guard_trg`, `portal_events_flood_guard_trg`, `idx_leads_created_at`, `idx_messages_client_id_created_at` |

**Advisors depois:** 73 avisos, todos `WARN`. Correção de leitura: na primeira rodada eu cortei a saída em 30 KB e contei 16 `multiple_permissive_policies`; o número real já era 47 antes das migrations (é `Admin full access` + policy específica em 9 tabelas, mais as duas policies duplicadas de `kanban_tasks` contadas para 6 papéis). Nenhuma das 7 migrations criou sobreposição nova; as de `internal_*` têm uma policy por ação. Restam: 8 de `SECURITY DEFINER` exposto (S6), 16 `auth_rls_initplan` (S8; os 2 de `users_see_own_*` sumiram), 1 `duplicate_index` em `kanban_tasks` (`idx_kanban_tasks_created_at` = `kanban_tasks_created_at_idx`, entra na Fase 2) e a proteção de senha vazada (dashboard).

Resíduos no banco: 3 hits em `rate_limits` para o IP de quem testou (somem na limpeza automática em 1 h). Nada mais.

### Só você consegue fazer (dashboard)

- Auth → Providers → Email → **desligar "Allow new users to sign up"** (S2). É o item mais importante que ainda está aberto.
- Auth → Attack Protection → **ligar leaked password protection** (S4).
- Auth → SMTP: conferir se é custom (Resend) ou built-in; Auth → Rate Limits (S5).
- Auth → CAPTCHA (Turnstile) em login/reset; depois validar o token no `submit-lead`.
- MFA para `super_admin`/`manager` (S4).

### Ainda em aberto (Fase 1 e 2)

Front: tirar os e-mails default do bundle e decidir admin pelo `profiles.role` (S4); checar `aal2` no AdminLayout quando o MFA entrar. Fase 2 inteira (S6, S7, S8 incluindo o `duplicate_index` de `kanban_tasks`, `create-invoice`, trigger de `updated_at`).

## 6. O que não consegui verificar

- **Logs** de Edge Functions / Postgres / Auth: a CLI não expõe e o token do Management API fica no Keychain, cuja leitura foi bloqueada nesta sessão. Se os "erros reportados" que você viu forem diferentes de E1 e E2, me passa o texto ou a tela que eu cruzo com o plano.
- **Configurações de Auth** (signup por e-mail confirmado só por probe; SMTP, CAPTCHA, MFA, rate limits): só pelo dashboard.
- **Plano do projeto** (free/pro) e cotas atuais de Storage/invocações: dashboard.

## 7. Inventário de referência

- Tabelas em `public` (17), todas com RLS: assets, client_files, deliveries, employee_notes, internal_files, internal_messages, invoices, kanban_tasks, leads, messages, newsletter_subscribers, portal_events, processed_payments, profiles, projects, rate_limits, weekly_goals.
- Funções em `public`: check_rate_limit (só service_role), deliveries_client_update_guard, get_vault_secret (só service_role), guard_profile_role, handle_new_user (só service_role), is_admin, is_team, leads_flood_guard.
- Buckets: avatars (público, 5 MB, imagens), pixelry-assets (público, 50 MB, vazio), client-uploads (privado, **sem limite**), deliveries (privado, **sem limite**, 18 MB usados), internal-files (privado, 50 MB).
- Edge Functions: create-client, create-employee, create-invoice (verify_jwt on); sync-notion, submit-lead, payment-webhook (verify_jwt off, autorização interna).
- Usuários: 5 (2 super_admin, 1 manager, 1 employee, 1 client), nenhum anônimo. Leads: 0. Faturas: 1. Banco: 13 MB.
