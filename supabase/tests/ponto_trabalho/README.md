# Testes do banco — Ponto e Trabalho

Suíte oficial dos testes de banco do módulo Ponto e Trabalho (contrato:
`docs/PONTO_TRABALHO_DESIGN.md` do app, §2, §3 e §5). Testa a migration
`supabase/migrations/20261101170000_ponto_trabalho.sql` num **PostgreSQL 17.5
local e descartável**. Nunca fala com a produção: não usa a CLI do Supabase, não
faz `db push/pull/query/link`, não acessa `*.supabase.co` e não baixa nada.

Os testes foram escritos **a partir do contrato**, não da migration: são a
checagem independente dela.

## Como rodar

```sh
cd supabase/tests/ponto_trabalho
npm install          # instala as duas devDependencies fixas (funciona offline com o cache do npm)
npm test             # = node run.mjs
```

Variações:

| comando | o que faz |
|---|---|
| `npm test` | suíte padrão (papéis aceitos hoje) + pendências globais + concorrência |
| `PONTO_SIMULAR_PAPEIS_NOVOS=1 npm test` | também roda `sql/new_roles/`, ampliando `profiles_role_check` **só** no banco descartável e **só** dentro da transação de cada arquivo |
| `node run.mjs --filtro 13_` | só os arquivos cujo caminho contém o texto (útil na triagem) |
| `node run.mjs --sem-concorrencia` | pula `concurrency.test.mjs` |
| `node run.mjs --somente-harness` | só stub + helpers + `sql/00_*` (não precisa da migration) |
| `PONTO_CONCORRENCIA_N=16` / `PONTO_CONCORRENCIA_RODADAS=30` | mais conexões simultâneas / mais rodadas de saída × intervalo |
| `PONTO_TZ=UTC` | fuso da sessão (padrão `Pacific/Kiritimati`, ver abaixo) |
| `PONTO_MIGRATION=/caminho/x.sql` | testa outro arquivo no lugar da migration (só para validar o próprio harness) |
| `npm run test:contract` | replay do contrato app Dart × SQL real (`contract/`, seção própria abaixo) |
| `PONTO_SIMULAR_PAPEIS_NOVOS=1 npm run test:contract` | o replay também roda partner, sales_trial, employee_dev e sdr |

Saída: uma linha por asserção (`ok` / `FALHA` / `FALHA ESPERADA (pendência
global)`), com o papel real da conexão entre colchetes (`[authenticated]`,
`[anon]`, `[postgres]`…), e um resumo no fim. **Exit code 1** se houver qualquer
falha que não seja de `sql/global/`. Sem a migration, o runner para com uma
mensagem clara e exit 1.

## O que o runner faz

1. Sobe um Postgres numa **porta livre** e num **diretório temporário**
   (`persistent: false`, apagado no fim), só em `127.0.0.1`, sem socket Unix.
   O cluster nasce em **UTF8** (como o Supabase) com locale `C`: sem isso o
   embedded-postgres usaria SQL_ASCII, `char_length` contaria bytes e os
   limites/textos pt-BR não seriam testados de verdade.
2. Carrega `stub/supabase_stub.sql` e `sql/_helpers.sql`.
3. Cria quatro pessoas "semente", tira um **retrato do catálogo** e aplica a
   migration **duas vezes seguidas**, cada uma na própria transação (como a CLI).
   Confere: sem `begin/commit` no arquivo; 1ª e 2ª aplicações sem erro; retrato
   idêntico entre as duas (definições, ACLs, policies, triggers, funções,
   colunas, índices, constraints, comentários, privilégios padrão, papéis);
   nenhum objeto preexistente alterado (profiles, `is_admin`, `is_team`, grants,
   papéis) e nada novo pendurado neles; dados preexistentes intactos; tabelas
   novas vazias. Depois remove as sementes.
4. Roda cada `sql/*.test.sql` numa **conexão própria**, dentro de
   `begin … rollback` (o arquivo também abre e fecha a transação). Acusa arquivo
   interrompido por erro, arquivo que não chegou ao `tests.done()` e arquivo que
   deixou estado no banco.
5. `sql/new_roles/`: pulado com motivo enquanto o schema rejeitar os papéis
   novos (ver "Estratégia de papéis").
6. `sql/global/`: pendências globais conhecidas, com falha esperada.
7. `concurrency.test.mjs`: concorrência real (abaixo).
8. **3ª aplicação, com dados.** Confere que nenhum arquivo deixou sobra no
   catálogo (retrato igual ao da 2ª aplicação: os grants temporários do
   `sql/34` sumiram com o rollback), grava uma semente confirmada nas 7 tabelas
   do módulo (além do que a concorrência confirmou) e aplica a migration de
   novo: sem erro, retrato do catálogo idêntico e nenhuma linha alterada
   (hash de cada tabela antes e depois).

## Arquivos

| arquivo | cobertura |
|---|---|
| `stub/supabase_stub.sql` | ambiente Supabase segundo as migrations versionadas (abaixo) |
| `sql/_helpers.sql` | schema `tests`: `create_user`, `login/login_anon/login_without_sub/login_service/logout`, `ok/is/eq`, `query_is/query_true`, `rows_eq`, `affects`, `lives`, `throws` (message e/ou SQLSTATE exatos), `throws_detail` (message + SQLSTATE + `detail` pt-BR de §3.7), `throws_like`, `throws_constraint`, `denied`, `rls_denied`, `admin_*` (verdade do banco, sem RLS), variáveis (`capture/var/uvar/jvar`), horário de Brasília (`brt`, `today_brt`, `midnight_brt`) |
| `sql/00_harness.test.sql` | autoteste do harness e do stub (não depende da migration) |
| `sql/01_schema_atual.test.sql` | o schema atual REJEITA partner/sales_trial/employee_dev/sdr; o módulo não mexe em profiles/is_admin/is_team; helpers `pt_*` por papel |
| `sql/10_ponto_sequencia.test.sql` | entrada → intervalo → retorno → saída; `time_my_status`; cada código de batida; formato do JSON (§3.4); auditoria de cada batida (ordem por `seq`, autor, before/after, `clock_timestamp()`) |
| `sql/11_ponto_idempotencia.test.sql` | mesmo `p_request_id` devolve a mesma jornada; outra ação → `request_id_conflict`; saída com intervalo aberto + repetição; `break_end` implícito com request_id nulo; id único por autor; correção/anulação/manual repetidas; request_id reaproveitado em OUTRA jornada nunca a altera |
| `sql/12_ponto_meia_noite_totais.test.sql` | `work_date` em Brasília (inclusive a armadilha do UTC); view `time_shift_totals` (colunas, `security_invoker`, horas descontando intervalos, abertos medidos até `now()`, `on_break`, `crosses_midnight`, anuladas) |
| `sql/13_ponto_correcao.test.sql` | cada código de validação da correção e a ordem entre eles; `p_breaks` nulo (SQL ou JSON) ou elemento nulo → `invalid_breaks`, sem apagar os intervalos; `future_timestamp` com tolerância zero (1 s à frente já é futuro); justificativa aparada de qualquer espaço em branco (tab, quebra de linha, NBSP, U+3000, BOM… como o `String.trim` do app) e limites contados em caracteres; substituição da lista de intervalos; auditoria antes/depois/autor/justificativa/data; review_status (dono → pending; super_admin + aberta → pending; super_admin + encerrada → reviewed); trava após revisão; anuladas; sobreposição |
| `sql/14_ponto_anulacao_manual.test.sql` | anulação (inclusive de jornada aberta em intervalo: intervalo e jornada fechados em `v_now`, UMA auditoria com o before como estava; justificativa acima de 1000 caracteres rejeitada); jornada manual (quem cria para quem, validações, `p_breaks` nulo, review_status) |
| `sql/15_ponto_revisao.test.sql` | revisão só do super_admin; null (SQL ou JSON)/vazio → 0; `p_shifts` malformado (objeto, elemento sem `updated_at`, id que não é uuid…) rejeitado sem revisar nada; `shift_changed`, `shift_open`, `shift_not_found`; já revisada ignorada; ids repetidos; tudo ou nada; anulada pendente |
| `sql/16_ponto_oraculo.test.sql` | manager/employee em jornada alheia aberta, encerrada, revisada, anulada ou inexistente → sempre `shift_not_found`, antes de qualquer validação; client/desconhecido → `not_allowed`; sem sub → `not_authenticated` |
| `sql/17_ponto_codigos_erro.test.sql` | tabela §3.7 de ponta a ponta: cada código provocado pelo caminho real, com `message`, SQLSTATE e o `detail` pt-BR exatos (triggers de integridade/auditoria como postgres) |
| `sql/20_ponto_rls.test.sql` | RLS por papel (manager NÃO vê o ponto alheio; super_admin vê tudo; client/desconhecido/sem sub nada; anon sem SELECT/EXECUTE) e nenhuma escrita direta nas tabelas de ponto (nem `setval`/`nextval` nas sequências de `seq`, nem `private.time_shift_json` direto) |
| `sql/21_ponto_integridade.test.sql` | **como postgres, de propósito**: checks, exclusões, índices únicos parciais, triggers imediatos de intervalo e jornada (inclusive troca de dono), `updated_at`, FKs restrict/cascade, auditoria imutável (postgres, service_role, authenticated) |
| `sql/30_tarefas_rls.test.sql` | tarefas: quem cria para quem, `invalid_assignee`, grants por coluna, validações, visibilidade, sem DELETE, evento `created` |
| `sql/31_tarefas_regras.test.sql` | regras de coluna do trigger (responsável que não criou só muda status, sem `canceled`; criador; só super_admin reatribui, e quem não pode ouve `task_field_not_allowed` antes de `invalid_assignee`), `completed_at` (também na criação já concluída)/`updated_at`, eventos `updated` com from/to exatos, histórico imutável |
| `sql/32_registros_entregas.test.sql` | registros e entregas: vínculo com jornada alheia/anulada/inexistente → 42501 (mesmo erro, sem oráculo); entrega em tarefa ou registro inexistente → 42501; entrega ligada a registro de outra tarefa → 42501; sem UPDATE/DELETE; validação de link; visibilidade; eventos sem vazar o registro |
| `sql/33_ponto_people.test.sql` | escopo exato do diretório `ponto_people()` |
| `sql/34_defesa_em_profundidade.test.sql` | segunda linha de defesa: com grants que o contrato NÃO dá abertos só na transação do arquivo, o trigger ainda barra `id`/`created_by`/`created_at` (responsável, criador e super_admin → `task_field_not_allowed`), força autor e datas no INSERT de tarefas/registros/entregas, mantém `completed_at`/`updated_at` do servidor (inclusive tarefa que continua concluída), e a falta de policy de escrita barra INSERT/UPDATE/DELETE direto no ponto, nas auditorias, DELETE de tarefa e UPDATE/DELETE de registros e entregas |
| `sql/40_grants_catalogo.test.sql` | armadilhas de §1/§3.0 lidas do catálogo: nenhuma função SECURITY DEFINER lê `current_user`/`session_user`/`current_role` (e só os três triggers INVOKER de §3.5 olham `current_user`); nenhuma policy compara uma coluna com ela mesma (coluna externa solta em subconsulta) e as subconsultas nomeiam a coluna externa pela tabela; grants (anon sem nada; sem MAINTAIN; colunas exatas; sequências identity de `seq` sem USAGE/SELECT/UPDATE para anon/authenticated), EXECUTE em `private` só nos três helpers, `search_path` vazio, RLS, policies, assinaturas das RPCs, constraints, índices, FKs, colunas, defaults |
| `sql/new_roles/01_ponto_papeis_novos.test.sql` | ponto com partner, sales_trial, employee_dev, sdr |
| `sql/new_roles/02_tarefas_papeis_novos.test.sql` | tarefas com os papéis novos (sdr não cria, vê só as atribuídas, só status; histórico/registros/entregas de tarefa que criou para outra pessoa fora do alcance; partner responsável só muda status) |
| `sql/global/01_profiles_escalada_delete_insert.test.sql` | pendência global §6.1: manager escala outra conta para super_admin via DELETE+INSERT em profiles |
| `concurrency.test.mjs` | concorrência real (abaixo) |
| `contract/replay.mjs` | replay do contrato: os pedidos HTTP capturados do app Dart executados contra a migration real (seção abaixo) |
| `contract/postgrest.mjs` | emulador mínimo do PostgREST v12 usado pelo replay |
| `contract/shapes.mjs` | formatos que os `fromJson` do Dart leem + conversão de instante igual à do `DateTime` do Dart |
| `contract/fixtures/time_tracking_requests.json`, `contract/fixtures/work_requests.json` | cópias das capturas dos testes Dart com servidor falso (método, caminho, query, corpo, cabeçalhos) |

## Como os casos rodam

- **Papel real.** Cada caso roda como `authenticated` (ou `anon`) com
  `request.jwt.claims` preenchido, trocando o papel com `set_config('role', …)`
  como o PostgREST faz. A única exceção é `21_ponto_integridade`, que escreve como
  `postgres` de propósito para provar que os triggers e constraints barram
  linhas inválidas mesmo fora das RPCs. Os `tests.admin_*` só **conferem** a
  verdade do banco (contagens exatas sem RLS); aparecem como `[postgres]`.
- **Nada de RETURNING em INSERT sob RLS** (o RETURNING exige policy de SELECT):
  os inserts usam ids gerados "no cliente" e contam linhas.
- **Erros exatos.** `tests.throws` compara a `message` (o código do contrato,
  ex. `shift_not_found`) e o SQLSTATE (§3.7); `tests.throws_detail` também a
  frase pt-BR do `detail`. Toda asserção de erro roda numa subtransação que é
  sempre desfeita.
- **Resiliência.** Uma asserção que falha não interrompe o arquivo; erro
  inesperado dentro de um helper vira falha com SQLSTATE e mensagem.
- **Fuso exótico.** A sessão roda em `Pacific/Kiritimati` (UTC+14): qualquer
  cálculo de data que dependa do fuso da sessão, em vez de `America/Sao_Paulo`
  explícito, aparece como falha.
- **Datas fixas no passado** (outubro de 2026) para jornadas manuais; as abertas
  usam o relógio real.

## Concorrência (`concurrency.test.mjs`)

Conexões separadas, **autocommit**, READ COMMITTED, entrando como
`authenticator` + `SET ROLE authenticated` (como o PostgREST). Para as N
chamadas partirem juntas, cada uma passa por uma "largada" independente da
migration (`with largada as materialized (select pg_advisory_xact_lock_shared(K)) select rpc(...)`);
o teste só solta a largada quando vê as N conexões esperando em `pg_locks`.

Cenários: N× entrada → 1 jornada (demais `shift_already_open`); N× intervalo →
1 intervalo aberto (`break_already_open`); N× retorno; N× saída; mesmo
`request_id` de N conexões → todas recebem a mesma jornada e há 1 linha de
auditoria (entrada, intervalo e saída fechando intervalo); saída × intervalo
simultâneos em várias rodadas → sempre o estado de uma ordem serial válida; N
pessoas ao mesmo tempo; N chamadas presas no advisory lock da chave do contrato
(`hashtextextended('ponto.time:' || uid, 0)`), com `time_my_status` respondendo
na hora enquanto o lock está preso ("Sem lock", §3.3); N× jornada manual sobreposta → 1
(`shift_overlap`); N× anulação → 1 (`shift_voided`); duas revisões simultâneas →
1 revisada e a outra `shift_changed`; revisão de jornadas de duas pessoas com
o advisory lock da pessoa de maior uuid preso → a chamada segura o da menor
enquanto espera (ordem crescente de uuid, §3.3 passo 4); listas `[A, B]` × `[B, A]`
simultâneas em várias rodadas → nunca `40P01` (deadlock), uma revisa as duas e a
outra recebe `shift_changed`; **oráculo pelo lock**: com o advisory lock de uma
pessoa preso, manager/employee corrigindo, anulando, revisando ou lançando
jornada manual dela respondem na hora (`shift_not_found`/`not_allowed`, §3.3
passo 3 antes do 4), enquanto o super_admin (controle) espera o lock; **mesmo
`request_id` do super_admin para duas pessoas ao mesmo tempo** (A numa transação
aberta, B parado no índice único esperando A) → B recebe `request_id_conflict`
(P0001 + frase de §3.7, nunca `23505` cru) e desfaz o que fez (§3.3 passo 7).

## Stub do Supabase

`stub/supabase_stub.sql` reproduz o que as **migrations versionadas** descrevem
(a fonte é o histórico do repositório, nunca a produção):

- papéis `anon`, `authenticated` (NOLOGIN NOINHERIT), `service_role` (BYPASSRLS)
  e `authenticator` (LOGIN NOINHERIT, membro dos três);
- schemas `auth` (`users`, `uid()/role()/email()/jwt()` lendo
  `request.jwt.claims`) e `extensions`;
- privilégios padrão do Supabase em `public` (ALL em tabelas/sequências/funções
  para anon/authenticated/service_role; no PG 17 isso inclui MAINTAIN);
- `public.profiles` com as colunas do histórico, `profiles_role_check`
  **exatamente** como na 20260608015308, RLS e as policies finais ("Users can
  view own profile", "Admin full access" FOR ALL com `is_admin()`,
  `employees_see_assigned_clients`, `team_members_see_each_other`,
  `profiles_update_own`), grants por coluna e `profiles_guard_role`
  (20260902000050);
- `is_admin()` (super_admin ou manager), `is_team()`, `handle_new_user` com os
  grants finais (incluindo o revoke/revert de 20260903).

Observação: a 20260607210944 cria `role` com um CHECK inline que o Postgres
nomearia `profiles_role_check`, e a 20260608015308 adiciona outra
`profiles_role_check`; as duas não convivem. O stub reproduz o estado final (a
da 20260608015308).

## Estratégia de papéis (decisão do Ezer)

- A suíte padrão usa só os papéis que o schema aceita hoje: **super_admin,
  manager, employee, client** e **"desconhecido"** (usuário autenticado sem linha
  em profiles).
- `01_schema_atual` confirma que o schema atual **rejeita** partner,
  sales_trial, employee_dev e sdr (documenta a pendência §6.2).
- `sql/new_roles/` fica **PULADO** (com o motivo impresso) enquanto o schema
  rejeitar esses papéis. `PONTO_SIMULAR_PAPEIS_NOVOS=1 npm test` amplia a
  constraint só no banco descartável, dentro da transação de cada arquivo. Se um
  dia o schema aceitar os papéis, a pasta roda sem simulação.
- Nenhuma alteração global é feita (a constraint real não é tocada).

## Pendências globais (`sql/global/`)

Testes de problemas **anteriores ao módulo**, descritos no contrato (§1, §6.1).
Cada asserção descreve o comportamento correto; hoje falham e aparecem como
`FALHA ESPERADA (pendência global)` sem derrubar a suíte. Se todas passarem, o
runner avisa para remover a marcação (mover o arquivo para `sql/`).

- `01_profiles_escalada_delete_insert`: um manager apaga o perfil de uma segunda
  conta e o reinsere com `role = 'super_admin'` (dois pedidos PostgREST comuns);
  a conta vira super_admin para o módulo e vê o ponto de todos.

## Contrato app × SQL (`contract/`)

`npm run test:contract` prova que os repositórios Flutter e o SQL concordam, sem
rede, sem PostgREST e sem binário novo: reexecuta o que o Dart envia contra a
migration real, como o PostgREST executaria.

**Entrada.** As capturas dos testes de repositório do app com servidor HTTP
falso (`test/features/*/data/supabase_*_repository_test.dart`): o pedido EXATO
de cada método (`fixtures/time_tracking_requests.json` é o arquivo que o teste
do ponto confere byte a byte; `fixtures/work_requests.json` sai de
`WORK_WIRE_OUT=<arquivo> flutter test test/features/work/data/supabase_work_repository_test.dart`).
Para atualizar, gere de novo no app e copie para `contract/fixtures/`.

**Execução.** Sobe um PostgreSQL 17.5 descartável (porta livre ou
`PONTO_PORTAS=55640-55659`, diretório temporário, `persistent: false`), carrega
`stub/supabase_stub.sql` e a migration e semeia pessoas por papel com os ids das
capturas (super_admin, manager, employee, client e uma conta sem perfil; com
`PONTO_SIMULAR_PAPEIS_NOVOS=1`, também partner, sales_trial, employee_dev e
sdr, ampliando a constraint só nesse banco). Cada pedido vira o SQL que o
PostgREST geraria (`postgrest.mjs`) e roda numa transação própria, conectado
como `authenticator` e com `set_config('role', 'authenticated'|'anon')` +
`request.jwt.claims`:

- **RPC** `POST /rest/v1/rpc/<fn>`: a função é resolvida pelo nome e pelas
  CHAVES do corpo, como no cache de schema do PostgREST (toda chave é parâmetro;
  todo parâmetro sem default veio), e chamada com argumentos nomeados a partir
  de `json_to_record($1) AS _(p_x <tipo do parâmetro>, …)`. Parâmetro com nome
  errado → `PGRST202`; valor que não converte → o erro do Postgres (22P02,
  22008…). Função não VOLATILE roda em transação somente leitura.
- **GET** `/rest/v1/<tabela>?select=…`: filtros `eq/neq/gt/gte/lt/lte/is/in`
  (com `not.`), `order=col.asc|desc.nullsfirst|nullslast`, embutido 1-N/N-1
  pela FK (`time_breaks(*)`, com `time_breaks.order`); transação READ ONLY.
- **POST/PATCH**: colunas = chaves do corpo (`json_to_recordset`/`json_to_record`
  com os tipos das colunas), `RETURNING *`; coluna sem grant de INSERT/UPDATE
  falha com 42501, como de verdade.
- `Accept: application/vnd.pgrst.object+json` (`.single()`): exatamente 1
  linha, senão `PGRST116` (406) e a transação é desfeita.
- Recurso do PostgREST que o app não usa e o emulador não conhece é erro do
  EMULADOR, nunca um "passou" silencioso.

**Verificações.**

1. *Estática*, por captura: toda RPC, parâmetro nomeado, tipo, tabela, coluna,
   embutido e grant que o Dart usa existe na migration, com tipo compatível com
   o valor JSON enviado (uuid, instante ISO, `YYYY-MM-DD`, booleano, jsonb);
   authenticated com EXECUTE/SELECT/INSERT/UPDATE de coluna e anon sem nada.
2. *Dinâmica*: um roteiro com estado (bater ponto, repetir com o mesmo
   `p_request_id`, intervalo, saída com e sem `p_close_open_break`, corrigir
   jornada aberta e encerrada, jornada manual, anular, revisar, criar tarefa,
   repetir o insert, registrar, entregar, mudar status, cancelar, reatribuir…)
   em que cada pedido dá o status/código esperado para o papel que o envia,
   inclusive as recusas por RLS/RPC (manager não vê nem corrige o ponto
   alheio; client e conta sem perfil sem acesso; anon sem EXECUTE). Ids gerados
   no CLIENTE que precisam de outro valor no roteiro são trocados (`remap`); o
   `updated_at` da revisão, gerado pelo SERVIDOR, é trocado pelo real
   convertido como o `DateTime` do Dart faz (ida e volta com microssegundos).
   Toda captura precisa de pelo menos um passo, senão o replay falha.
3. *Formato*: toda chave que o `fromJson` do Dart lê está PRESENTE na resposta
   real (mais estrito que o Dart, que trata ausente como null), com instantes
   ISO 8601 com fuso, datas `YYYY-MM-DD`, `time_breaks` sempre lista e em ordem,
   `server_now` nas RPCs (e só nelas), inteiros como número JSON.

O roteiro roda em duas bases: sessão em `UTC` (como o Supabase) e em
`Pacific/Kiritimati` (+14:00). `PONTO_TZ=<fuso>` roda um só.

**Volta para o Dart.** `node contract/replay.mjs --gravar <pasta>` grava as
respostas reais (`time_tracking_real_responses.json`, `work_real_responses.json`,
só os papéis aceitos hoje). Copiadas para `test/features/*/data/fixtures/` do
app, alimentam `real_sql_contract_test.dart`: cada passo é refeito pelo
repositório Dart de verdade contra o servidor falso, que devolve o status e o
corpo REAIS. O teste confere que o pedido do Dart é idêntico ao que o replay
executou, que o `fromJson` aceita a resposta, que o erro vira o texto de §3.7,
que a repetição com 23505 real devolve o registro existente e que o
`WorkAccess` oferece exatamente o que o trigger aceitou.

`PONTO_MIGRATION=<arquivo>` e `PONTO_FIXTURES=<pasta>` trocam a migration e as
capturas (só para validar o próprio replay com mutantes).

## Limites

- O stub cobre só o que o módulo usa; outras tabelas do Supabase (deliveries,
  storage…) não existem aqui.
- `postgres` é superusuário no Postgres local (no Supabase não é, mas é dono das
  tabelas e ignora a RLS delas do mesmo jeito).
- O PostgREST não está no circuito: os testes chamam as RPCs e as tabelas em
  SQL, com o mesmo papel e o mesmo JWT que o PostgREST usaria. O replay
  (`contract/`) emula a tradução HTTP → SQL do PostgREST v12 para os recursos
  que o app usa; não é o binário do PostgREST (sem rede e sem binário novo).
  Diferenças possíveis em recursos fora desse conjunto não são cobertas.
- O replay não pagina: o `db-max-rows` do Supabase (1000 por padrão) cortaria
  em silêncio listas maiores, e as listas do app não paginam.
- `TRUNCATE` por service_role/postgres não dispara triggers de linha; a
  imutabilidade da auditoria vale para UPDATE/DELETE (como no contrato).
