# Tarefa 001 - Bronze de games (LeagueGameLog) particionada e idempotente

- Status: A fazer
- Estimativa: 1 a 2 dias (8 a 14 horas), divididas em 3 entregas pequenas (ver "Plano sugerido")
- Depende de: ADR 001 (`docs/adr/001-formato-e-particionamento-bronze-games.md`). Leia a ADR antes de escrever uma linha de código.

## Contexto e motivação de negócio

O objetivo da empresa é prever o campeão da NBA. Qualquer modelo precisa, no mínimo, do histórico de resultados: quem jogou contra quem, quando, onde e com que desempenho. Hoje só temos dimensões estáticas (players e teams). Sem a tabela de jogos não existe fato, portanto não existe silver nem gold analítica.

Esta é também a primeira vez que o pipeline lida com dado **transacional que muda ao longo do tempo**. Os arquivos atuais (`players_raw`, `teams_raw`) são sobrescritos inteiros e não têm risco de duplicação. Games exige pensar em idempotência, reprocessamento, limites da API e falhas parciais, que são exatamente os temas que diferenciam um script de um pipeline.

Fonte: `nba_api.stats.endpoints.leaguegamelog.LeagueGameLog` com `player_or_team_abbreviation='T'`, que retorna **uma linha por time por jogo** (cada `game_id` aparece 2 vezes). Há um rascunho em `notebooks/testes.ipynb`; use como exploração, não como base de implementação (veja riscos).

## Objetivo

Ingerir o game log de times para a camada bronze, particionado por `season` e `season_type` conforme a ADR 001, de forma **idempotente**, com tratamento de falhas da API e escrita atômica.

Escopo de temporadas: de `2015-16` até `2025-26` (última temporada completa; a 2026-27 ainda não começou), com os 3 tipos (`Regular Season`, `Playoffs`, `PlayIn`). O intervalo deve ser parâmetro, não constante espalhada.

## Critérios de aceite

Cada item deve poder ser verificado por um comando, teste ou consulta. Anexe a evidência na descrição do PR.

**Estrutura e formato**
1. Após o backfill, existe `data/bronze/games/season=YYYY-YY/season_type=<slug>/games.parquet` para cada combinação que a API devolveu com linhas. Slugs permitidos: `regular_season`, `playoffs`, `play_in`.
2. Não existe arquivo para combinações com 0 linhas (ex.: `play_in` em `2015-16`). A execução loga explicitamente "0 linhas, partição ignorada" para elas.
3. Os arquivos usam compressão zstd (verificável via metadados do Parquet) e leem corretamente com `pl.scan_parquet("data/bronze/games/**/*.parquet", hive_partitioning=True)`, expondo `season` e `season_type` como colunas.
4. O schema é definido por uma constante explícita no código (padrão já usado em `extract.py`), com nomes de coluna em snake_case minúsculo. `game_id` é string e preserva zeros à esquerda (ex.: `0022400001`). `team_id` é inteiro. `game_date` permanece string ISO.
5. Cada arquivo contém as colunas de metadado `_ingested_at` (UTC) e `_source` (nome do endpoint).

**Qualidade dos dados (consultas de validação, escritas por você em SQL ou Polars e guardadas no repositório)**
6. Em toda partição, o par `(game_id, team_id)` é único (zero duplicatas).
7. Em toda partição, cada `game_id` aparece exatamente 2 vezes, com `team_id` distintos. Exceção documentada, se existir, deve estar listada no PR com explicação.
8. Nenhuma partição tem mais de 30 `team_id` distintos, e `season_id` não é nulo em nenhuma linha.
9. O total de linhas de `regular_season` de `2024-25` é compatível com 30 times x 82 jogos = 2.460. Se divergir, o PR explica por quê.

**Idempotência e robustez**
10. Rodar o backfill duas vezes seguidas produz o mesmo conjunto de arquivos e a mesma contagem de linhas por partição; o conteúdo das colunas de origem (excluindo `_ingested_at`) é idêntico. Evidência: comparação de contagem e de um hash das colunas de origem antes e depois da segunda execução.
11. Rodar para uma única `(season, season_type)` reescreve só aquela partição; os demais arquivos mantêm o `mtime` inalterado.
12. Simular falha no meio da escrita (por exemplo, exceção forçada após criar o arquivo temporário em um teste) não deixa o `games.parquet` anterior corrompido nem deixa arquivo temporário residual no diretório.
13. Falhas transitórias da API (timeout, 429/5xx simulados) são tentadas novamente com backoff exponencial e número máximo de tentativas configurável. Após esgotar tentativas, a execução registra a partição como falha, **continua** com as demais e termina com código de saída diferente de zero. Verificável com teste que usa mock da chamada.
14. Há pausa configurável entre requisições (padrão >= 1 s) e timeout explícito na chamada. Valores vêm de configuração, não ficam fixos no meio da lógica.

**Engenharia**
15. A função que converte o ano inicial em string de temporada tem testes, incluindo `1999 -> "1999-00"` e `2025 -> "2025-26"`. Nenhum `"-25"` ou ano hardcoded no código de produção.
16. A lógica de escrita e de validação tem testes com `pytest` que **não acessam a rede** (a chamada à API é injetada ou mockada). `pytest` passa localmente em ambiente limpo.
17. A execução tem CLI mínima (por exemplo `python -m src.extract_games --start 2015 --end 2025 --season-type "Regular Season"`), com `--help` funcional. Sem argumentos, o comportamento é documentado no README.
18. O log final de cada execução imprime, por partição, `season`, `season_type`, número de linhas, status (ok / vazia / falha) e duração.
19. `data/` continua no `.gitignore`; nenhum arquivo de dados nem credencial é commitado. O `README` ganha a seção "Como rodar a ingestão de games" com os comandos exatos.

## Fora de escopo

- Silver (cast de `game_date`, dedup para uma linha por jogo, join com teams). Será a tarefa seguinte.
- Box score por jogador, play-by-play e qualquer outro endpoint.
- Orquestração (cron, Airflow, etc.) e agendamento.
- Migração para S3.
- Padronizar o tipo de `id` em `players_raw` e `teams_raw` (débito registrado na ADR 001).
- Ingestão incremental diária / atualização da temporada corrente por jogo. Aqui, atualizar a temporada corrente é simplesmente reexecutar sua partição.
- Cache de respostas da API, paralelismo e proxies.

## Plano sugerido (entregas pequenas, um PR cada se preferir)

1. **Núcleo puro**: schema, função de temporada, mapeamento de `season_type` para slug, função de caminho da partição, escrita atômica. Tudo testável sem rede (critérios 4, 12, 15, 16).
2. **Extração resiliente**: chamada à API com timeout, retry/backoff, pausa entre requisições, tratamento de partição vazia (critérios 2, 13, 14).
3. **CLI, backfill e validação**: orquestração do loop, log, código de saída, consultas de qualidade, README (critérios 1, 3, 5 a 11, 17 a 19).

## Riscos

- **Bloqueio/limite do stats.nba.com**: o endpoint é não oficial, lento e pode rejeitar requisições (timeout, 429, bloqueio por IP). Hoje roda do seu notebook e funciona; **a partir de IPs de nuvem (AWS) costuma ser bloqueado**. Isso é um insumo importante para a futura decisão de onde executar a ingestão, então anote o comportamento observado (latência, erros) para o `docs/mentoria.md` ou para uma ADR futura.
- **Rascunho do notebook engana**: ele muta a variável do laço (`ano`) dentro do próprio `for` e fixa `ano_seguinte = 25`. Não migre esse padrão. Derive a string de temporada de uma única fonte (a função do critério 15).
- **Mudança de schema da fonte**: a nba_api pode adicionar/renomear colunas. Mitigação: schema explícito falha alto (erro claro) em vez de gravar coluna inesperada em silêncio.
- **Temporada corrente parcial**: dados de uma temporada em andamento mudam; não trate a contagem de linhas dela como invariável (critério 9 vale só para temporada fechada).
- **Falsa idempotência**: `_ingested_at` muda a cada execução. Valide idempotência pelo conteúdo das colunas de origem, não pelo hash do arquivo.
- **Windows**: `os.replace` e caminhos com espaço; use `pathlib` e teste o fluxo atômico no seu ambiente.

## O que você aprende

Idempotência por partição, escrita atômica, particionamento Hive, contratos de schema, retry com backoff e limites de API, testes sem rede (injeção de dependência/mock), CLI e códigos de saída. Tudo reaproveitável quando o mesmo desenho for para o S3 e para um orquestrador.

## Perguntas para a entrevista técnica (use como autoverificação)

- Por que partição por temporada e não por data? Em que condição você mudaria de ideia?
- Como você prova que a ingestão é idempotente?
- O que acontece se o processo morrer na metade de uma escrita? E se a API cair na 17ª de 33 chamadas?
