# Financeiro — operação do backend

Contrato: `docs/FINANCEIRO_DESIGN.md` no repositório do app (seções 3 a 5).
Este arquivo cobre aplicar, verificar, desligar e remover. Nada aqui tem ref de
projeto, segredo ou dado real: o repositório é público.

## O que o pacote instala

| migration | conteúdo |
|---|---|
| `20261101174500_finance_access.sql` | schema `finance_private`, `public.finance_access_grants`, nível de acesso (`level_for`, `is_owner`, `access_level`, `can_read`, `can_manage`), RPCs `finance_my_access`, `finance_set_access`, `finance_access_list` |
| `20261101174510_finance_entries.sql` | `public.finance_categories`, `public.finance_entries`, índices (inclusive `idx_invoices_due_date` e `idx_invoices_paid_at` em `invoices`), RLS, gatilhos `touch` e `block_delete` |
| `20261101174520_finance_audit.sql` | `finance_private.module_info`, `public.finance_audit_log`, guarda da auditoria, gatilhos de auditoria (estrito nas tabelas do financeiro, **tolerante** em `public.invoices`) |
| `20261101174530_finance_api.sql` | RPCs de leitura (`finance_ledger`, `finance_overview_meta`, `finance_entry_history`, `finance_clients`) e de alteração (`finance_create_entry`, `finance_correct_entry`, `finance_settle_entry`, `finance_cancel_entry`, `finance_reverse_entry`, `finance_create_category`, `finance_set_category_archived`) |

A guarda de papel no INSERT de `profiles`, que era a `20261101174540`, foi
levada para a migration compartilhada da integração
(`20261102120000_shared_roles_and_profiles_security.sql`, trigger
`profiles_guard_insert_role` em `public`), junto com a revogação de
INSERT/DELETE de `authenticated` em `profiles`. O financeiro não depende mais
de nada em `profiles` além de `role`.

Só acrescenta. Não muda as colunas, o CHECK de papéis, as policies nem os
grants de `profiles`, nem `is_admin()`, `is_team()`, as policies de
`invoices`, o dashboard ou as Edge Functions. Objeto novo em tabela
existente:

- `finance_audit_invoice_trg` (AFTER, por linha, em `public.invoices`) e os
  dois índices. O gatilho nunca levanta erro: qualquer falha vira `WARNING` e
  a escrita do create-invoice, do webhook ou do dashboard segue.

Ninguém ganha acesso ao financeiro ao aplicar: só o `super_admin` lê e altera.
Os demais papéis internos precisam de concessão explícita (`finance_set_access`,
pelo app, na tela "Acesso ao financeiro").

## Aplicar

1. **Só a partir de uma branch integrada** com as migrations de todos os
   pacotes (CRM, Ponto, Financeiro), nunca do worktree de um pacote. A ordem é
   a dos timestamps: CRM `20261101150000–150400` → Ponto `20261101170000` →
   Financeiro `20261101174500–174530` → integração `20261102120000`.
2. **Antes de produção:**
   - `supabase/tests/finance/run.sh --bootstrap` num Postgres local
     descartável (ver `supabase/tests/finance/README.md`);
   - se houver homologação: `supabase db push --db-url <homologação>` e depois
     `run.sh --skip-migrations` contra ela.
3. `supabase db push --dry-run` e conferir a lista **exata**: devem aparecer só
   as migrations que ainda não estão no remoto, na ordem acima.
4. Se aparecer *"Remote migration versions not found in local migrations
   directory"*: **não** use `supabase migration repair --status reverted`. Traga
   para a branch os arquivos que faltam (eles existem em outro pacote/branch).
5. `supabase db push`.

## Verificar (somente leitura)

Depois do push, no SQL Editor (são só `select`; nada é gravado):

```sql
-- 14 RPCs, nenhuma executável por anon, todas por authenticated
select count(*) as rpcs,
       count(*) filter (where has_function_privilege('anon', p.oid, 'EXECUTE')) as anon,
       count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE')) as authenticated
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'finance\_%';
-- esperado: 14 | 0 | 14

-- Tabelas: RLS ligada, anon e service_role sem nenhum privilégio, authenticated só SELECT
select c.relname, c.relrowsecurity,
       has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE') as anon,
       has_table_privilege('service_role', c.oid, 'SELECT, INSERT, UPDATE, DELETE') as service_role,
       has_table_privilege('authenticated', c.oid, 'SELECT') as auth_select,
       has_table_privilege('authenticated', c.oid, 'INSERT, UPDATE, DELETE') as auth_write
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname like 'finance\_%' and c.relkind = 'r';
-- esperado: 4 linhas | true | false | false | true | false

-- Gatilho de auditoria de invoices ligado
select tgname, tgenabled from pg_trigger
where tgrelid = 'public.invoices'::regclass and tgname = 'finance_audit_invoice_trg';
-- esperado: 1 linha, tgenabled = 'O'

-- Guarda compartilhada de papel no INSERT de profiles ligada (20261102120000)
select tgname, tgenabled from pg_trigger
where tgrelid = 'public.profiles'::regclass and tgname = 'profiles_guard_insert_role';
-- esperado: 1 linha, tgenabled = 'O'

-- authenticated sem INSERT/DELETE em profiles (20261102120000)
select has_table_privilege('authenticated', 'public.profiles', 'INSERT'),
       has_table_privilege('authenticated', 'public.profiles', 'DELETE');
-- esperado: false | false

-- is_admin/is_team continuam executáveis (as policies dependem disso)
select has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE'),
       has_function_privilege('authenticated', 'public.is_team()', 'EXECUTE');
-- esperado: true | true
```

Depois, no dashboard, confira o fluxo normal: uma cobrança nova aparece, o
webhook confirma pagamento, o cancelamento funciona. Nos logs do Postgres, um
`WARNING: finance_audit_invoice falhou (sqlstate …)` indica que a auditoria de
uma invoice não foi gravada (a escrita em si seguiu). Se repetir, use o passo 1
do rollback e investigue.

## Conceder acesso

Pelo app (o super_admin, em "Acesso ao financeiro"), que chama
`finance_set_access(p_user_id, p_level, p_reason)` e grava o motivo na
auditoria. Níveis: `none`, `read`, `manage`. Só papéis internos (`partner`,
`manager`, `sales_trial`, `sdr`, `employee_dev`, `employee`) recebem acesso;
`client` nunca, mesmo com linha gravada.

Pelo SQL Editor (como `postgres`, quando o app ainda não estiver disponível):

```sql
-- Um único DO: o motivo (local à transação) e o insert ficam juntos.
do $$
begin
  perform set_config('pixelry.finance_change_reason', '<motivo, 5 a 500 caracteres>', true);
  insert into public.finance_access_grants (user_id, level, reason)
  values ('<uuid do profile>', 'read', '<mesmo motivo>')
  on conflict (user_id) do update
    set level = excluded.level, reason = excluded.reason, updated_at = now();
end $$;
```

A auditoria registra `actor_role = 'postgres'` e `actor_id` nulo. Concessão
gravada para um `client` ou `super_admin` não tem efeito (o nível é calculado
pelo papel).

## Desligar e remover — `rollback.sql`

**Passo 1 — interruptor (seguro a qualquer momento, não perde dados):**

```sql
drop trigger if exists finance_audit_invoice_trg on public.invoices;
```

É a primeira instrução de `rollback.sql`. Rodar o arquivo sem mais nada aplica
só este passo e avisa que o passo 2 não foi executado.

**Religar a auditoria de invoices** (o histórico entre desligar e religar não
existe):

```sql
drop trigger if exists finance_audit_invoice_trg on public.invoices;
create trigger finance_audit_invoice_trg
  after insert or update or delete on public.invoices
  for each row execute function finance_private.audit_invoice();
```

**Passo 2 — remoção completa (DESTRÓI lançamentos, categorias, concessões e a
auditoria; só com decisão explícita do Ezer):** na mesma execução, antes do
arquivo,

```sql
set pixelry.finance_remove_all = 'apagar-tudo';
```

e então o conteúdo de `rollback.sql`. Remove as 14 RPCs, as 4 tabelas, os
dois índices de `invoices`, o schema `finance_private` e as 4 versões em
`supabase_migrations.schema_migrations`. A guarda de `profiles` é da migration
de integração e não é removida aqui. Antes, exporte o que precisar guardar
(`finance_entries`, `finance_audit_log`).

Sem as RPCs, o app mostra "Financeiro ainda não está disponível neste
servidor" (erro `PGRST202`) e nada mais quebra.

## Limites conhecidos

- A auditoria de invoices começa em `finance_private.module_info.audit_installed_at`;
  não há histórico de cobranças anterior.
- `invoices` ainda pode ser apagada pelo dashboard (policy `Admin full access`)
  e em cascata ao apagar o usuário do cliente. O ledger mantém a cobrança a
  partir do snapshot do evento `deleted`, mas a linha original some.
- `paid_at` é a hora do processamento do webhook, não a liberação do dinheiro;
  estornos e chargebacks do Mercado Pago não chegam ao banco.
- A exclusão de profiles pela API (policy `Admin full access` + DELETE de
  `authenticated`), que a seção 11 do contrato deixava para a integração,
  foi fechada pela `20261102120000`: `authenticated` não tem mais INSERT nem
  DELETE em `profiles`.
