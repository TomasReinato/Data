# Tarefa 001 - Bronze de games (LeagueGameLog) particionada e idempotente

- Status: A fazer
- Estimativa: 1,5 a 2 dias (10 a 16 horas), divididas em 3 entregas pequenas (ver "Plano sugerido"). A revisão de 2026-10-11 acrescentou ~2 h (tabela de contagens, validação de schema, guarda de regressão).
- Depende de: ADR 001 (`docs/adr/001-formato-e-particionamento-bronze-games.md`). Leia a ADR antes de escrever uma linha de código.

## Contexto e motivação de negócio

O objetivo da empresa é prever o campeão da NBA. Qualquer modelo precisa, no mínimo, do histórico de resultados: quem jogou contra quem, quando, onde e com que desempenho. Hoje só temos dimensões estáticas (players e teams). Sem a tabela de jogos não existe fato, portanto não existe silver nem gold analítica.

Esta é também a primeira vez que o pipeline lida com dado **transacional que muda ao longo do tempo**. Os arquivos atuais (`players_raw`, `teams_raw`) são sobrescritos inteiros e não têm risco de duplicação. Games exige pensar em idempotência, reprocessamento, limites da API e falhas parciais, que são exatamente os temas que diferenciam um script de um pipeline.

Fonte: `nba_api.stats.endpoints.leaguegamelog.LeagueGameLog` com `player_or_team_abbreviation='T'`, que retorna **uma linha por time por jogo** (cada `game_id` aparece 2 vezes). Há um rascunho em `notebooks/testes.ipynb`; use como exploração, não como base de implementação (veja riscos).

## Objetivo

Ingerir o game log de times para a camada bronze, particionado por `season` e `season_type` conforme a ADR 001, de forma **idempotente**, com tratamento de falhas da API, validação de schema que falha alto e escrita atômica.

Escopo de temporadas: de `2015-16` até `2025-26` (11 temporadas; a 2025-26 é a última encerrada, a 2026-27 ainda não começou), com os 3 tipos (`Regular Season`, `Playoffs`, `PlayIn`). O intervalo deve ser parâmetro, não constante espalhada.

## Contagens esperadas por temporada (referência para os critérios 1, 7 e 9)

Regra geral: cada jogo gera **exatamente 2 linhas** (uma por time). Logo, linhas = 2 x jogos.


| Temporada | Regular Season (jogos / linhas) | PlayIn (jogos / linhas) | Playoffs (jogos) | Certeza | Observação |
|---|---|---|---|---|---|
| 2015-16 a 2018-19 (4 temporadas) | 1.230 / 2.460 cada | 0 (partição inexistente) | entre 60 e 105 | Alta (regular), faixa derivada (playoffs) | 30 x 82 / 2 = 1.230 |
| 2019-20 | **1.059 / 2.118** | **1 / 2 segundo a Wikipedia; ver incerteza abaixo** | ~85 (aproximado) | Média | Pandemia: suspensa em março/2020, retomada na bolha de Orlando. Cada time jogou entre 64 e 75 jogos (não 82). 171 jogos do calendário original nunca aconteceram. |
| 2020-21 | **1.080 / 2.160** | 6 / 12 | 85 / 170 | Alta | Calendário reduzido: 72 jogos por time, todos os 1.080 jogados apesar de 31 adiamentos. |
| 2021-22 a 2024-25 (4 temporadas) | 1.230 / 2.460 cada | 6 / 12 cada | entre 60 e 105 | Alta (regular, play-in), faixa derivada (playoffs) | |
| 2025-26 | 1.230 / 2.460 | 6 / 12 | entre 60 e 105 | Média | Ver incerteza sobre NBA Cup abaixo. |

Como ler a coluna Playoffs: são 16 times e 15 séries melhor-de-7, cada uma com no mínimo 4 e no máximo 7 jogos, logo **60 a 105 jogos (120 a 210 linhas)**. É um limite matemático, não um número por temporada. Só confirmei por fonte o total de 2020-21 (85 jogos: 43 + 24 + 12 + 6 por rodada). Não pesquisei temporada a temporada os demais totais de playoffs, então não os inventei: se quiser contagem exata, use a faixa agora e fixe o valor observado na fixture após conferir com uma fonte (veja critério 9).

**Incertezas que você precisa resolver observando a API (e registrar no PR):**

1. **2019-20, play-in.** A Wikipedia trata o jogo Portland x Memphis de agosto/2020 (vaga de 8º do Oeste) como o único play-in da história pré-2021. Não sei como o `stats.nba.com` etiqueta esse jogo: pode vir em `PlayIn` (2 linhas), em `Playoffs`, ou em `Regular Season`. Consulte as três combinações de 2019-20 e registre onde ele aparece. Isso decide se o backfill gera 28 ou 29 arquivos (critério 1).
2. **2019-20, playoffs.** O total de ~85 jogos vem da soma de placares de séries numa página com texto parcialmente truncado; trate como aproximado. Se o jogo de play-in estiver etiquetado como `Playoffs`, some mais 1.
3. **2025-26 e NBA Cup.** Pelas regras, os jogos da fase de grupos e do mata-mata da Cup contam para a temporada regular, **exceto a final** (16/12/2025). Os 22 times fora do mata-mata jogam 2 jogos extras para fechar 82. O total de 1.230 é aritmética (30 x 82 / 2), não um número que tenha visto numa fonte. Não sei se o `LeagueGameLog` devolve os jogos de mata-mata da Cup em `Regular Season` nem se devolve a final em algum lugar. Se a contagem divergir de 2.460, investigue antes de "ajustar a expectativa".
4. Os totais de 2019-20 (1.059) e 2020-21 (1.080) vêm de fontes que somam GP ou citam o calendário; a Wikipedia diz "63-67 jogos por time antes da suspensão" e a soma de GP na tabela de classificação dá 2.118 linhas de time. Confirme contra a API: o número da API prevalece, mas diferença precisa de explicação escrita no PR.

Fontes:
- 2019-20 (GP por time, play-in, chaveamento): https://en.wikipedia.org/wiki/2019%E2%80%9320_NBA_season
- Play-in por temporada (1 jogo em 2020; 6 por ano de 2021 a 2026): https://en.wikipedia.org/wiki/NBA_play-in_tournament
- 2020-21 (72 jogos, estrutura e resultados das séries): https://www.nba.com/news/history-season-review-2020-21 e https://pr.nba.com/2020-21-nba-season-structure
- NBA Cup 2025 (o que conta para a temporada regular): https://en.wikipedia.org/wiki/2025_NBA_Cup
- Colunas do endpoint: código-fonte da nba_api, `src/nba_api/stats/endpoints/leaguegamelog.py`

## Critérios de aceite

Cada item deve poder ser verificado por um comando, teste ou consulta. Anexe a evidência na descrição do PR.

**Estrutura e formato**
1. Após o backfill, existe `data/bronze/games/season=YYYY-YY/season_type=<slug>/games.parquet` para cada combinação que a API devolveu com linhas. Slugs permitidos: `regular_season`, `playoffs`, `play_in`. A grade teórica é 11 temporadas x 3 tipos = 33. Para o escopo 2015-16 a 2025-26, o resultado esperado é **28 arquivos**: 11 `regular_season` + 11 `playoffs` + 6 `play_in` (2020-21 a 2025-26), ou seja 33 menos 5 combinações vazias (play-in de 2015-16 a 2019-20). Se a API devolver o jogo de play-in de 2019-20 (incerteza 1), o esperado passa a **29**; nesse caso o PR documenta que a partição `season=2019-20/season_type=play_in` tem exatamente 2 linhas. Qualquer outro número é falha ou precisa de explicação. Verificável contando os arquivos `games.parquet` sob `data/bronze/games/`.
2. Não existe arquivo para combinações com 0 linhas **e schema válido** (ex.: `play_in` em `2015-16`). A execução loga explicitamente "0 linhas, partição ignorada" para elas. Uma resposta sem as colunas esperadas **não é** partição vazia: é falha (critério 21).
3. Os arquivos usam compressão zstd (verificável via metadados do Parquet) e leem corretamente com `pl.scan_parquet("data/bronze/games/**/*.parquet", hive_partitioning=True)`, expondo `season` e `season_type` como colunas. O glob não pode capturar arquivos temporários (critério 12).
4. O schema é definido por uma constante explícita no código (padrão já usado em `extract.py`), com nomes de coluna em snake_case minúsculo. `game_id` é string e preserva zeros à esquerda (ex.: `0022400001`). `team_id` é inteiro. `game_date` permanece string ISO. A lista de colunas da fonte deve ser conferida contra a versão da `nba_api` instalada (o código-fonte atual do endpoint declara 29 colunas, de `SEASON_ID` a `VIDEO_AVAILABLE`); fixe a versão da lib no `requirements`/`pyproject`.
5. Cada arquivo contém as colunas de metadado `_ingested_at` (UTC) e `_source` (nome do endpoint).

**Qualidade dos dados (consultas de validação, escritas por você em SQL ou Polars e guardadas no repositório)**
6. Em toda partição, o par `(game_id, team_id)` é único (zero duplicatas).
7. Em toda partição, cada `game_id` aparece exatamente 2 vezes, com `team_id` distintos. Exceção documentada, se existir, deve estar listada no PR com explicação.
8. Nenhuma partição tem mais de 30 `team_id` distintos, e `season_id` não é nulo em nenhuma linha.
9. As contagens de linhas das partições de temporadas encerradas batem com a tabela "Contagens esperadas" acima, materializada como fixture versionada (CSV ou dict no repositório) e checada por teste ou consulta de validação: `regular_season` e `play_in` com **igualdade exata** (2.460 para as temporadas de 82 jogos, 2.118 em 2019-20, 2.160 em 2020-21, 12 no play-in a partir de 2020-21) e `playoffs` dentro da faixa 120 a 210 linhas (par). Divergência não é ajustada em silêncio: o PR explica por quê, citando fonte. Uma partição `regular_season` ou `playoffs` com 0 linhas em temporada do escopo é **falha**, não "vazia".

**Idempotência e robustez**
10. Rodar o backfill duas vezes seguidas produz o mesmo conjunto de arquivos e a mesma contagem de linhas por partição; o conteúdo das colunas de origem (excluindo as colunas de metadado `_ingested_at` e `_source`) é idêntico. Evidência: contagem e hash das colunas de origem antes e depois da segunda execução. O hash deve (a) **ordenar as linhas por `(game_id, team_id)` antes de calcular**, para não depender da ordem em que a API devolve os dados, (b) usar as colunas na ordem fixada pela constante de schema e (c) usar um algoritmo estável entre execuções e versões de biblioteca (por exemplo SHA-256 sobre uma serialização canônica; o `hash_rows` do Polars só garante estabilidade dentro da mesma versão, então não use como evidência de longo prazo). Teste sem rede: o mesmo conteúdo com linhas embaralhadas gera o mesmo hash; alterar um único valor gera hash diferente. A ordenação é determinística porque o critério 6 garante unicidade da chave; rode a checagem de unicidade antes do hash.
11. Rodar para uma única `(season, season_type)` reescreve só aquela partição; os demais arquivos mantêm o `mtime` inalterado.
12. Escrita atômica com arquivo temporário **que não casa com o glob de leitura**: o temporário fica no mesmo diretório da partição com nome `games.parquet.tmp` (extensão final `.tmp`, nunca `.parquet`), e só vira `games.parquet` via `os.replace` ao final. Teste: simular falha no meio da escrita (exceção forçada após criar o temporário) não corrompe o `games.parquet` anterior, e o glob `data/bronze/games/**/*.parquet` não retorna o temporário nem durante a escrita. Em falha tratada dentro do processo, o temporário é removido.
13. Retry com backoff exponencial e número máximo de tentativas configurável, cobrindo as falhas transitórias **reais** da stack (veja a seção "Falhas da nba_api" abaixo). Após esgotar tentativas, a execução registra a partição como falha, **continua** com as demais e termina com código de saída diferente de zero. Verificável com testes parametrizados que usam mock da chamada: cada classe de falha listada como "tentar de novo" é repetida até o máximo e o número de chamadas é exatamente `max_tentativas`; cada classe "não tentar de novo" resulta em exatamente 1 chamada.
14. Há pausa configurável entre requisições (padrão >= 1 s) e timeout explícito na chamada. Valores vêm de configuração, não ficam fixos no meio da lógica. (Contexto: o `LeagueGameLog` usa `timeout=30` por padrão, mas a camada HTTP da nba_api usa `None`, ou seja, sem timeout, se alguém chamá-la direto. Não dependa do padrão: passe o valor explicitamente.)
20. **Limpeza no início da execução.** Antes de qualquer requisição, a execução remove temporários residuais (`*.tmp` sob `data/bronze/games/`) deixados por um processo que morreu (kill, queda de energia), e loga cada arquivo removido. Teste: criar `games.parquet.tmp` manualmente numa partição, rodar, e verificar que sumiu e que `games.parquet` existente não foi tocado. Só vale por causa da premissa de processo único (ADR 001); não rode a limpeza se houver outra execução em andamento.
21. **Falha alta para schema inesperado.** Se a resposta da API tiver conjunto de colunas diferente do schema declarado (coluna a mais, a menos, renomeada), ou se um cast explícito falhar (ex.: `game_id` nulo, `team_id` não inteiro), a execução levanta erro com mensagem que lista as colunas faltantes e as extras, **não grava nada** para aquela partição, mantém intacto o `games.parquet` anterior, marca a partição como falha, segue com as demais e termina com código de saída diferente de zero. Erro de schema **não** é tentado de novo (não é transitório). Teste sem rede com DataFrame mockado: coluna extra, coluna ausente, coluna renomeada e resposta sem result set/sem colunas, cada uma resulta em falha, nenhum arquivo novo e nenhum `.tmp`.
22. **Guarda de regressão antes de sobrescrever** (consequência da ADR 001, "custo de perder a versão anterior"). Se já existe `games.parquet` para a partição e o novo download tem **menos linhas** que o existente, a escrita é recusada, a partição é marcada como falha com mensagem clara, e o arquivo antigo permanece. Um parâmetro explícito (por exemplo `--allow-shrink`) libera a sobrescrita e fica registrado no log. Teste sem rede cobrindo: mais linhas (sobrescreve), mesmas linhas (sobrescreve), menos linhas (recusa), menos linhas com a flag (sobrescreve).

**Engenharia**
15. A função que converte o ano inicial em string de temporada tem testes, incluindo `1999 -> "1999-00"` e `2025 -> "2025-26"`. Nenhum `"-25"` ou ano hardcoded no código de produção.
16. A lógica de escrita e de validação tem testes com `pytest` que **não acessam a rede** (a chamada à API é injetada ou mockada). `pytest` passa localmente em ambiente limpo.
17. A execução tem CLI mínima (por exemplo `python -m src.extract_games --start 2015 --end 2025 --season-type "Regular Season"`), com `--help` funcional. Sem argumentos, o comportamento é documentado no README.
18. O log final de cada execução imprime, por partição, `season`, `season_type`, número de linhas, status (ok / vazia / falha) e duração. Para falhas, inclui a classe do erro (ex.: `ReadTimeout`, `SchemaError`, `RegressionGuard`).
19. `data/` continua no `.gitignore`; nenhum arquivo de dado nem credencial é commitado. O `README` ganha a seção "Como rodar a ingestão de games" com os comandos exatos.

## Falhas da nba_api (base dos critérios 13, 18 e 21)

Conferido no código-fonte atual da nba_api (`library/http.py`, `stats/endpoints/_base.py`, `leaguegamelog.py`). Confirme contra a versão que você instalar, porque a lib não tem garantia de estabilidade:

- A nba_api faz a requisição com `requests` (sessão compartilhada) e **não captura exceções do `requests`**: elas sobem para você.
- A nba_api **não verifica o status HTTP**: não há `raise_for_status()`. Uma resposta 429 ou 5xx **não vira exceção**; o corpo (muitas vezes vazio ou HTML) é entregue ao parser. Na prática a falha costuma aparecer depois, como erro de JSON inválido ou como resultado sem colunas. O status fica guardado no objeto de resposta do endpoint (confira o nome exato do atributo na versão instalada); para tratar 429/5xx como tal você precisa lê-lo, não esperar uma exceção.
- O parse usa `json.loads`, então corpo inválido levanta `json.JSONDecodeError` (subclasse de `ValueError`). A nba_api só levanta uma `Exception` genérica de "InvalidResponse" se `raise_exception_on_error` for ligado, o que não é o padrão. Não faça `except Exception` genérico.
- Quando a resposta não tem cabeçalhos de result set, `get_data_frame()` devolve um `DataFrame` **vazio e sem colunas** em vez de erro. Isso é perigoso: uma resposta bloqueada pode se passar por "partição vazia". Por isso o critério 2 distingue "0 linhas com schema válido" de "sem colunas".

**Tentar de novo (transitórias):**
- `requests.exceptions.Timeout` (inclui `ConnectTimeout` e `ReadTimeout`; o erro "Read timed out (read timeout=30)" é o mais relatado nas issues do projeto).
- `requests.exceptions.ConnectionError` (DNS, conexão recusada/resetada; `ConnectTimeout` herda de ambas).
- `requests.exceptions.ChunkedEncodingError` (conexão cortada no meio do corpo).
- `json.JSONDecodeError` / `ValueError` no parse do corpo (corpo vazio ou HTML de bloqueio).
- Status HTTP 429 (respeitando `Retry-After` se vier) e 5xx (500, 502, 503, 504), detectados pelo status guardado na resposta.

**Não tentar de novo:**
- Erro de schema ou de cast (critério 21): determinístico.
- Status 4xx diferente de 429 (400 = parâmetro errado; 403 costuma indicar bloqueio de IP, e insistir só piora). Logue com dica de bloqueio.
- Exceções de programação (`KeyError`, `TypeError`) e `KeyboardInterrupt`.

Nota de honestidade: não consegui verificar por fonte qual dessas exceções aparece com cada tipo de bloqueio do `stats.nba.com` (as issues do projeto, como as de timeout em IPs de nuvem, descrevem sobretudo timeouts). Você vai descobrir isso na prática; registre no `docs/mentoria.md` o que observar.

## Fora de escopo

- Silver (cast de `game_date`, dedup para uma linha por jogo, join com teams). Será a tarefa seguinte.
- Box score por jogador, play-by-play e qualquer outro endpoint.
- Orquestração (cron, Airflow, etc.) e agendamento.
- Migração para S3 (incluindo versionamento de bucket, mencionado na ADR 001 só como mitigação futura).
- Padronizar o tipo de `id` em `players_raw` e `teams_raw` (débito registrado na ADR 001).
- Ingestão incremental diária / atualização da temporada corrente por jogo. Aqui, atualizar a temporada corrente é simplesmente reexecutar sua partição.
- Backup/snapshot de versões anteriores da partição (a ADR 001 escolhe só a guarda de regressão do critério 22).
- Cache de respostas da API, paralelismo e proxies.

## Plano sugerido (entregas pequenas, um PR cada se preferir)

1. **Núcleo puro**: schema, função de temporada, mapeamento de `season_type` para slug, função de caminho da partição, escrita atômica com `.tmp`, limpeza inicial, hash de conteúdo, validação de schema e guarda de regressão. Tudo testável sem rede (critérios 4, 10 (hash), 12, 15, 16, 20, 21, 22).
2. **Extração resiliente**: chamada à API com timeout, retry/backoff por classe de erro, leitura do status HTTP, pausa entre requisições, tratamento de partição vazia vs. sem colunas (critérios 2, 13, 14).
3. **CLI, backfill e validação**: orquestração do loop, log, código de saída, consultas de qualidade, fixture de contagens esperadas, README (critérios 1, 3, 5 a 11, 17 a 19).

## Riscos

- **Bloqueio/limite do stats.nba.com**: o endpoint é não oficial, lento e pode rejeitar requisições (timeout, 429, bloqueio por IP). Hoje roda do seu notebook e funciona; **a partir de IPs de nuvem (AWS) costuma ser bloqueado** (há issues no repositório da nba_api relatando timeouts em Heroku e outros provedores). Isso é um insumo importante para a futura decisão de onde executar a ingestão, então anote o comportamento observado (latência, erros) para o `docs/mentoria.md` ou para uma ADR futura.
- **Rascunho do notebook engana**: ele muta a variável do laço (`ano`) dentro do próprio `for` e fixa `ano_seguinte = 25`. Não migre esse padrão. Derive a string de temporada de uma única fonte (a função do critério 15).
- **Mudança de schema da fonte**: a nba_api pode adicionar/renomear colunas. Mitigação: critério 21 (falha alta, nada gravado) e versão da lib fixada.
- **Falso "vazio"**: resposta bloqueada sem colunas pode parecer partição sem jogos e, pior, nunca ser retentada. Mitigação: critérios 2 e 9.
- **Temporada corrente parcial**: dados de uma temporada em andamento mudam; não trate a contagem de linhas dela como invariável (critério 9 vale só para temporada encerrada).
- **Temporadas atípicas**: 2019-20 e 2020-21 não têm 82 jogos por time; qualquer validação genérica "82 jogos" quebra nelas. É a razão da tabela e da fixture do critério 9.
- **Falsa idempotência**: `_ingested_at` muda a cada execução, e a ordem das linhas da API pode variar. Valide idempotência pelo conteúdo das colunas de origem ordenado por `(game_id, team_id)` (critério 10), não pelo hash do arquivo.
- **Perda da versão anterior**: sobrescrever a partição destrói a versão boa se a API devolver dado pior (ver ADR 001). Mitigação parcial no critério 22; ela não detecta valores errados com a mesma contagem de linhas.
- **Windows**: `os.replace` e caminhos com espaço; use `pathlib` e teste o fluxo atômico no seu ambiente. No Windows, `os.replace` pode falhar com `PermissionError` se o destino estiver aberto por outro processo (por exemplo um notebook com o arquivo carregado); isso é falha da partição, não motivo de retry silencioso.

## O que você aprende

Idempotência por partição, escrita atômica e limpeza de resíduos, particionamento Hive, contratos de schema e falha alta, retry com backoff e classificação de erros transitórios vs. permanentes, limites de API, testes sem rede (injeção de dependência/mock), CLI e códigos de saída. Tudo reaproveitável quando o mesmo desenho for para o S3 e para um orquestrador.

## Perguntas para a entrevista técnica (use como autoverificação)

- Por que partição por temporada e não por data? Em que condição você mudaria de ideia?
- Como você prova que a ingestão é idempotente? Por que o hash precisa ordenar as linhas e excluir `_ingested_at`?
- O que acontece se o processo morrer na metade de uma escrita? E se a API cair na 17ª de 33 chamadas?
- Por que a nba_api devolver 429 não gera exceção, e como isso muda o seu retry?
- Se a API devolver menos linhas do que você já tinha, o que o pipeline faz e por quê?
