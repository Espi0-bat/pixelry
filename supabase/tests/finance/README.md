# Suíte SQL do financeiro

Testa permissões, RLS, regras dos lançamentos, auditoria e a compatibilidade
com `invoices` (create-invoice, payment-webhook e cancelamento do dashboard).
Contrato: `docs/FINANCEIRO_DESIGN.md`, seção 4, no repositório do app.

> **Produção não é ambiente de teste.** Rode num Postgres local descartável ou
> em homologação. Nunca em produção, nem "dentro de transação com rollback".

**Estado:** executada em 2026-11-02 num PostgreSQL 17.11 local descartável:
migrations aplicadas duas vezes e 232/232 casos passando. A primeira rodada
exigiu um ajuste no harness (`pg_temp.u()` precisa ser VOLATILE; veja o
comentário na função e o autoteste `harness_u_sees_fixture_from_same_command`).
Rodar de novo em homologação continua pendência antes do `db push`.

## Arquivos

| arquivo | papel |
|---|---|
| `run.sh` | trava de segurança, aplica as migrations duas vezes e roda a suíte |
| `fixtures/00_supabase_stub.sql` | só para Postgres puro: papéis `anon`/`authenticated`/`service_role`, `auth.users`, `auth.uid()`/`role()`/`email()`/`jwt()` iguais aos do Supabase, default privileges do Supabase em `public`. Não faz nada se `auth.users` existir. |
| `fixtures/01_baseline_public.sql` | só para Postgres puro: `profiles`, `is_admin()`, `is_team()` e `invoices` no estado efetivo das migrations versionadas (o cabeçalho cita a origem de cada trecho). Não faz nada se `public.profiles` existir. |
| `finance_rls.test.sql` | os casos (232), numa transação que termina em `ROLLBACK` |

As migrations antigas não reconstroem o banco do zero (tabelas criadas fora
delas, CHECK com nome repetido), por isso `supabase db reset` não serve e a
suíte traz a própria baseline.

## Como rodar

Requer `psql` (cliente do Postgres) e um servidor Postgres 15+ (o Supabase usa
17). Nada é baixado por estes scripts.

### Postgres local descartável

```sh
createdb finance_test
DATABASE_URL=postgres://postgres:postgres@localhost:5432/finance_test \
  supabase/tests/finance/run.sh --bootstrap
dropdb finance_test   # opcional: a suíte não deixa nada, mas o stub e a baseline ficam
```

Conecte como `postgres` (superusuário). Os casos de auditoria esperam
`actor_role` igual ao usuário da sessão, que no Supabase é `postgres`.

### Homologação (projeto Supabase separado de produção)

```sh
supabase db push --db-url "<url de homologação>"     # aplica as migrations
DATABASE_URL="<url de homologação>" FINANCE_FORBIDDEN_REFS="<ref de produção>" \
  supabase/tests/finance/run.sh --skip-migrations
```

Use a conexão direta (porta 5432 do host do banco) ou o pooler em modo
sessão. O `run.sh` liga a trava do harness por `PGOPTIONS`; se o pooler não
repassar a opção, a suíte recusa rodar (falha segura).

## Trava de segurança do `run.sh`

- Exige `DATABASE_URL`. Só usa `psql`: nunca `supabase db query`, nunca
  `--linked` (o argumento é recusado).
- Recusa `hostaddr=` e `service=` na `DATABASE_URL` e `PGHOSTADDR`/`PGSERVICE`
  no ambiente: com eles o host real não aparece e a trava não consegue
  conferi-lo.
- Recusa o destino (`DATABASE_URL`, `PGHOST`, `PGUSER`) se contiver qualquer
  ref proibida, sem diferenciar maiúsculas. É uma conferência de texto: o host
  precisa aparecer pelo nome (`db.<ref>.supabase.co`, ou o pooler com usuário
  `postgres.<ref>`); um IP escrito direto na URL não é conferido. A lista é:
  - `FINANCE_FORBIDDEN_REFS` (separada por vírgula ou espaço), e
  - a ref do projeto linkado, lida de `supabase/.temp/project-ref` ou de
    `supabase/.temp/linked-project.json`, que o Supabase CLI grava localmente
    e o `.gitignore` mantém fora do repositório.

  Nenhuma ref fica escrita neste repositório (ele é público). Na máquina de
  quem já rodou `supabase link` no projeto de produção, a ref de produção é
  detectada sozinha.
- Sem nenhuma ref conhecida, só aceita banco local (`localhost`, `127.0.0.1`,
  `::1` ou socket), numa forma sem dúvida sobre o host: todo `host=` (da URI
  ou de `chave=valor`, com ou sem espaços em volta do `=`) precisa ser local,
  sem lista de hosts (vírgula), sem `%XX` depois do `?` e sem `PGHOST`. Isso
  barra, por exemplo, `postgresql:///postgres?host=<remoto>` e
  `host=localhost.exemplo.com`.
- Recusa migration do financeiro com `begin`/`commit`/`rollback`/`start
  transaction`/`concurrently`.
- Confere que o total de casos declarado no fim da suíte bate com as chamadas
  de `pg_temp.chk` (caso esquecido não passa calado).
- A própria suíte recusa rodar sem `pixelry.finance_test_harness = on`, e a
  primeira linha (`\set ON_ERROR_STOP on`) faz o SQL Editor rejeitar o arquivo.

## Flags

| flag | uso |
|---|---|
| `--bootstrap` | banco vazio: aplica stub + baseline, depois as migrations |
| `--skip-migrations` | homologação com as migrations já aplicadas por `supabase db push --db-url` |
| (nenhuma) | banco que já tem Supabase/baseline mas não as migrations do financeiro |

Sem `--skip-migrations`, as 5 migrations rodam em ordem, cada uma numa
transação (`psql -1`), e **rodam de novo** em seguida: a segunda passagem é a
prova de idempotência.

## Como a suíte funciona

- Tudo numa transação; o último comando é `ROLLBACK`. Pessoas de teste
  (`finance-test-<uuid>@example.invalid`), cobranças, lançamentos e auditoria
  nascem e morrem nela. `lock_timeout` 10 s, `statement_timeout` 120 s e,
  no Postgres 17, `transaction_timeout` 300 s.
- Pessoas nascem por `insert` em `auth.users` (o perfil vem do gatilho
  `handle_new_user`) e recebem o papel por `update` como `postgres`.
  Os testes ponta a ponta usam só os papéis aceitos pelo CHECK atual
  (`super_admin`, `manager`, `employee`, `client`); os papéis futuros
  (`partner`, `sales_trial`, `sdr`, `employee_dev`, desconhecido, NULL) são
  testados chamando `finance_private.level_for` direto. Nenhum `alter table
  profiles`.
- Identidade: `pg_temp.as_actor(kind, uid)` zera claims, `request.jwt.claim.*`
  e `pixelry.finance_change_reason` a cada caso e só então faz `SET LOCAL
  ROLE` (`anon`, `authenticated` com `sub`, `service_role`, ou nenhum para
  `postgres`). O `SET ROLE` fica fora do bloco `begin … exception` de
  `pg_temp.attempt`/`pg_temp.val`, que capturam `sqlstate` e mensagem.
- Nenhum `INSERT` usa `RETURNING` sob RLS.
- Cada caso grava `(id, ok, detalhe)` numa tabela temporária com `grant all
  to public`. Um caso com resultado NULL conta como falha. Contagens de
  "não vê nada" sempre conferem antes, como `postgres`, que existe algo para
  ver.
- O caso de auditoria quebrada adiciona `finance_test_fail check (false) not
  valid` em `finance_audit_log` e o remove em seguida (tudo dentro da
  transação). Ele gera `WARNING: finance_audit_invoice falhou (sqlstate 23514)`
  na saída: é esperado.

## Saída

A suíte imprime uma linha por caso (`ok` ou `FALHOU`, com detalhe só nas
falhas), depois `passaram | falharam | total`. O `DO` final levanta exceção se
algum caso falhou, se algum id repetiu ou se o total for diferente do esperado;
então o `psql` sai com código diferente de 0 e o `run.sh` também.

Um erro fora de um caso (por exemplo, uma RPC que falha ao criar fixture)
aborta a suíte na hora, com a mensagem do Postgres: também é falha.

## Casos (ids)

- **Catálogo:** `rpcs_not_executable_by_anon`, `rpcs_executable_by_authenticated`,
  `private_functions_closed_to_anon_and_public`, `policy_helpers_executable`,
  `private_helpers_closed_to_authenticated`, `trigger_functions_closed`,
  `tables_closed_to_anon`, `tables_authenticated_select_only`,
  `tables_closed_to_service_role`, `audit_sequence_closed`, `module_info_closed`,
  `private_schema_usage`, `rls_enabled_on_finance_tables`,
  `invoice_audit_trigger_installed`.
- **Acesso e isolamento:** matriz `level_for_*`; `my_access_*` (super_admin,
  manager sem/com read/com manage, employee sem/com concessão, client com linha
  de concessão, sem perfil, anon); `ledger_denied_*`; `set_access_*`;
  ciclo `grant_lifecycle_audited`; `access_list_*`; visibilidade direta
  (`entries_hidden_*`, `audit_hidden_without_grant`, `grants_*`,
  `*_anon_no_select`); escrita direta recusada (`service_role_cannot_*`,
  `manage_cannot_*`, `owner_cannot_update_grants_directly`); `read_cannot_*`
  (cada RPC de escrita, com a linha conferida depois); quem não lê
  (`no_grant_*`, `client_with_grant_row_*`, `no_profile_*`: histórico,
  metadados e escrita); negativa explícita
  (`set_access_none_without_row_audited_removed`); profile novo pela API só
  como client (`manager_cannot_insert_privileged_profile`,
  `service_role_inserts_internal_profile`); auditoria de concessão
  (`grant_audit_visible_to_owner`, `grant_audit_visible_to_target`,
  `grant_audit_hidden_from_other_reader`).
- **Lançamentos:** criação e idempotência (`create_entry_*`), validações
  `22023`, correção (`correct_*`), liquidação (`settle_*`), cancelamento
  (`cancel_*`, `cancelled_is_final_*`), estorno (`reverse_*`,
  `ledger_reversed_by_id`, `cancel_original_with_active_reversal`,
  `cancel_reversal_clears_link`), cliente conferido mesmo com contraparte
  (`create_entry_client_checked_with_counterparty`), snapshot sem e-mail
  (`client_without_name_snapshot_has_no_email`), motivo zerado depois de cada
  mutação (`mutation_rpcs_clear_reason_after_dml`), DELETE/TRUNCATE recusados
  até para postgres (TRUNCATE de categorias pela mensagem exata), campos
  imutáveis, auditoria imutável e não forjável, `numeric(14,2)` e centavos
  exatos.
- **Invoices:** `invoice_status_*` (todos os status, inclusive NULL e
  cancelada com `paid_at`), `invoice_settled_on_sao_paulo`, draft fora do ledger
  e sem auditoria, `invoice_issue_audited_issued`, webhook
  (`invoice_webhook_*`), dashboard (`invoice_dashboard_cancel_*`), metadados
  sem auditoria, leitura pelo manager sem concessão e pelo cliente, auditoria
  quebrada (`audit_failure_*`), exclusão do usuário do cliente
  (`client_deletion_*`) e do autor (`creator_deletion_*`), cobrança apagada,
  recriada com o mesmo id e apagada de novo sem duplicar
  (`restored_invoice_listed_once`, `invoice_deleted_twice_listed_once`).
- **Fumaça:** `smoke_*` (toda RPC chamada com sucesso), janela do ledger,
  `total_rows`, ordem, `finance_overview_meta`, histórico e clientes.
