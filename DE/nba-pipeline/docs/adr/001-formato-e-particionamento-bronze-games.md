# ADR 001 - Formato e particionamento dos arquivos Parquet da bronze (games)

- Status: Aceita
- Data: 2026-10-11 (revisada no mesmo dia: temporadas atípicas, temporário `.tmp`, hash ordenado, schema que falha alto, custo de sobrescrever)
- Relacionada a: tarefa 001 (`docs/tasks/001-bronze-games-league-game-log.md`)

## Contexto

Hoje a bronze tem dois arquivos monolíticos (`data/bronze/players_raw.parquet` e `teams_raw.parquet`), sobrescritos por inteiro a cada execução. Isso funciona porque são dados estáticos, minúsculos e sem histórico. Games é diferente:

- Dado transacional que cresce todo ano e **muda dentro da temporada atual** (jogos novos a cada dia).
- Fonte: endpoint `LeagueGameLog` (nba_api), que retorna **uma linha por time por jogo** (cada `game_id` aparece 2 vezes) e é consultado por `(season, season_type)`. Já existe um rascunho dessa chamada em `notebooks/testes.ipynb`.
- Volume: ~2.460 linhas por temporada regular de 82 jogos (30 x 82), menos de 1 MB por temporada. Exceções reais: 2019-20 (pandemia, ~2.118 linhas) e 2020-21 (72 jogos por time, 2.160 linhas); ver tabela na tarefa 001. Em 10 anos, dezenas de MB. **Não é um problema de big data**; as decisões abaixo são sobre idempotência, reprocessamento e portabilidade para S3, não sobre performance bruta.
- A migração para S3 está planejada. O layout escolhido hoje será o prefixo de chaves de amanhã, e mudar layout depois significa reescrever tudo e ajustar leitores.

Precisamos decidir: (1) formato, (2) granularidade/particionamento, (3) compressão, (4) regras de nome e escrita.

## Opções consideradas

### Formato

| Opção | Prós | Contras |
|---|---|---|
| CSV | Legível, zero dependência | Sem tipos (game_id `0022400001` perde zeros à esquerda se alguém abrir no Excel/inferir int), sem schema, maior, lento, ambíguo com vírgulas em strings. Inadequado para bronze que precisa preservar o dado. |
| JSON bruto (resposta da API) | Preserva 100% da resposta, melhor para auditoria | Exige parse para qualquer uso, maior, schema implícito. Seria defensável em um projeto com muito risco de mudança de contrato; aqui o `LeagueGameLog` é tabular e estável. |
| **Parquet** | Schema embutido, colunar, comprimido, leitura nativa por Polars/DuckDB/Athena, consistente com o que já existe | Não é legível em editor de texto; schema evolution exige cuidado |
| Delta/Iceberg | MERGE, time travel, transações | Complexidade de catálogo/engine desproporcional para ~30 arquivos pequenos. Revisitar só se aparecer necessidade real de upsert em escala. |

### Particionamento

| Opção | Prós | Contras |
|---|---|---|
| A. Arquivo único `games_raw.parquet` (padrão atual) | Simplicidade máxima | Toda atualização reescreve tudo; sem reprocessamento seletivo; uma falha no meio corrompe o histórico inteiro; não escala como padrão para os próximos datasets (box score, play-by-play) |
| B. Partição por data (`game_date=YYYY-MM-DD/`) | Ingestão incremental diária natural; granular | ~1.230 jogos em ~165 dias por temporada regular, ou seja ~165 arquivos de poucos KB por ano. Problema clássico de **small files**: em S3/Athena o custo é por requisição e o overhead por arquivo domina a leitura. A API não é consultada por dia no nosso fluxo (o `LeagueGameLog` devolve a temporada inteira de uma vez), então a granularidade não casa com a fonte. |
| **C. Hive por `season` e `season_type`** (`season=2024-25/season_type=regular_season/`) | Casa com a **unidade natural da API** (um request = uma partição); reprocessar uma temporada é sobrescrever uma pasta; temporadas encerradas ficam imutáveis; poucos arquivos (3 tipos x N temporadas); formato Hive é entendido por Polars, DuckDB, Spark, Athena e Glue (inclusive com partition projection); temporada é eixo de análise natural para o modelo de previsão de campeão | Dentro da temporada atual a partição inteira é reescrita a cada atualização (barato: <1 MB). Não permite append incremental fino. |
| D. Apenas `season` (sem `season_type`) | Menos níveis | Atualizar playoffs obriga reescrever a regular season também; mistura unidades de request diferentes; perde a propriedade "uma chamada de API = um arquivo". |

### Compressão

- `snappy` (padrão histórico): rápido, compressão mediana.
- **`zstd`** (nível padrão): melhor razão de compressão, leitura rápida, suportado por pyarrow/Polars/Athena atuais. Em S3 o volume é irrelevante em custo, mas o hábito certo é gratuito.

## Decisão

1. **Formato: Parquet**, compressão **zstd**, com schema explícito definido em código (constante), não inferido.
2. **Particionamento: Hive por `season` e `season_type`**, um único arquivo por partição:

   ```
   data/bronze/games/
     season=2024-25/season_type=regular_season/games.parquet
     season=2024-25/season_type=playoffs/games.parquet
     season=2024-25/season_type=play_in/games.parquet
   ```

   - `season` no formato `YYYY-YY` (como a API). Atenção ao virar de século (`1999-00`).
   - `season_type` em slug minúsculo sem espaços (`regular_season`, `playoffs`, `play_in`), mapeado do valor da API ("Regular Season", "Playoffs", "PlayIn"). Espaços em chaves/pastas dão dor em S3, URLs e shell.
   - Nome do arquivo **determinístico** (`games.parquet`), nunca com timestamp. É o que torna a reexecução idempotente: mesma unidade de request, mesmo caminho, sobrescrita.
3. **Escrita atômica**: escrever em arquivo temporário no mesmo diretório e substituir (`os.replace`) ao final. Uma falha no meio nunca deixa um parquet truncado no lugar do bom. Em S3 o PUT de objeto já é atômico, então o padrão se mantém na migração.
   - O temporário se chama `games.parquet.tmp`: a extensão final **não é `.parquet`**, então o glob de leitura (`**/*.parquet`) jamais o enxerga, nem durante a escrita nem como resíduo. Um temporário terminado em `.parquet` seria lido como dado válido (e truncado) por qualquer consumidor.
   - **Limpeza no início da execução**: antes de qualquer requisição, apagar `*.tmp` residuais sob `data/bronze/games/` (processo morto no meio da escrita) e logar o que foi removido. Seguro apenas porque a execução é single-process (ver consequências).
4. **Partição vazia não gera arquivo, mas "vazia" tem definição estrita**: 0 linhas **com schema válido**. Temporadas sem play-in (2015-16 a 2018-19, e possivelmente 2019-20, ver abaixo) retornam 0 linhas; isso é logado, não persistido. Um arquivo vazio cria ambiguidade entre "não existe" e "falhou". Resposta sem colunas é falha, não vazia (a nba_api devolve `DataFrame` vazio e sem colunas quando o result set não vem, o que pode mascarar bloqueio como "partição sem jogos").
   - Correção em relação à versão inicial desta ADR: o play-in existe desde 2020-21 com 6 jogos por temporada, mas **2019-20 teve 1 jogo de play-in** (Portland x Memphis, bolha). Não sabemos como a API o etiqueta; a tarefa 001 manda observar e registrar. Resultado esperado do backfill 2015-16 a 2025-26: 28 arquivos (29 se esse jogo vier como `PlayIn`).
5. **Bronze preserva o dado da fonte**: sem dedup, sem joins, sem filtros. Permitido apenas: nomes de coluna em snake_case minúsculo, tipos explícitos e colunas de metadado. `game_id` é **string** (zeros à esquerda). `game_date` permanece string ISO como vem da API; o cast para `Date` é trabalho da silver. `team_id` permanece inteiro como na fonte.
6. **Colunas de metadado de ingestão**: `_ingested_at` (UTC) e `_source` (nome do endpoint). Consequência: arquivos não são idênticos byte a byte entre execuções; **idempotência é definida sobre o conteúdo das colunas de origem**, não sobre o hash do arquivo.
   - O hash de conteúdo **ordena as linhas por `(game_id, team_id)`** antes de calcular, usa as colunas na ordem do schema e exclui as colunas `_`-prefixadas. Sem a ordenação, a mesma resposta em outra ordem geraria hash diferente e a idempotência pareceria quebrada (falso positivo); a ordenação é total porque `(game_id, team_id)` é única na partição. Algoritmo estável (ex.: SHA-256 sobre serialização canônica), não o `hash_rows` do Polars, que só garante estabilidade dentro de uma versão.
   - Ordenar linhas na escrita por essa mesma chave é permitido (não altera conteúdo) e deixa o arquivo determinístico, mas a verificação de idempotência não pode depender disso.
7. `season` e `season_type` são lidos da estrutura de pastas (partition columns) e não precisam ser duplicados dentro do arquivo, mas a coluna `season_id` da fonte é mantida como veio.
8. **Schema inesperado falha alto.** O schema é um contrato declarado em código. Coluna a mais, a menos, renomeada ou cast que falha interrompe aquela partição com erro explícito (lista de diferenças), sem gravar nada e sem tocar o arquivo anterior; as demais partições seguem e o processo termina com código diferente de zero. Opção descartada: aceitar colunas novas automaticamente (schema evolution silenciosa). Ela deixaria a bronze com schemas diferentes entre partições, e o erro só apareceria na silver, longe da causa. O custo é aceito: uma mudança da API vai quebrar o job e exigir intervenção humana. Isso é o comportamento desejado.
9. **Sobrescrita da partição, com guarda de regressão.** Ver "Custo de perder a versão anterior" abaixo.

## Consequências

Positivas:
- Reprocessar uma temporada é `rm -r` de uma pasta e rodar de novo, ou simplesmente rodar de novo.
- Backfill pode ser paralelizado/retomado por partição (já preparando a orquestração futura, onde cada partição é uma task/pasta idempotente).
- Portabilidade direta para S3: `s3://bucket/bronze/games/season=.../season_type=.../games.parquet`, sem refatorar leitores.
- Poucos arquivos: custo de requisições S3 desprezível e leitura eficiente via Athena/DuckDB.

Negativas / custos assumidos (desconfortáveis, mas conscientes):
- **Mais trabalho que o padrão atual** de `players_raw.parquet`: é preciso construir caminho por partição, escrita atômica, mapeamento de `season_type` e logging por partição. É exatamente o aprendizado desta tarefa.
- A temporada corrente é reescrita inteira a cada atualização. Aceitável hoje (<1 MB); se um dataset futuro (ex.: play-by-play, milhões de linhas) tornar isso caro, aquele dataset terá sua própria ADR, possivelmente com partição por data.
- Sem proteção contra escrita concorrente de dois processos na mesma partição. Aceito: execução é single-process até haver orquestrador.
- Inconsistência conhecida: `players_raw` e `teams_raw` guardam `id` como string, enquanto `team_id` de games permanece inteiro. O join na silver exigirá cast explícito. Não vamos reescrever players/teams agora; fica registrado como débito técnico para uma tarefa futura de padronização de tipos.
- Os dois arquivos existentes (`players_raw`, `teams_raw`) continuam no layout antigo. Dados de referência pequenos e estáticos podem continuar assim; a regra desta ADR vale para datasets transacionais/históricos.

## Custo de perder a versão anterior ao sobrescrever a partição

A decisão 3 e a idempotência por sobrescrita têm um preço que precisa estar explícito: **depois do `os.replace`, a versão anterior da partição não existe mais.** Não há histórico, nem time travel, e `data/` não está no Git.

O que isso significa na prática:
- **Dado pior substitui dado bom.** O `stats.nba.com` não é oficial e não tem garantia. Se ele devolver uma resposta parcial (menos jogos), com valores corrigidos de forma errada ou com colunas zeradas, mas ainda com schema válido, a validação de schema passa e o arquivo bom é destruído.
- **Não dá para auditar mudanças.** Correções retroativas de estatísticas pela NBA ficam invisíveis: você não consegue responder "o que mudou entre a ingestão de março e a de junho?". Para um modelo de previsão, isso afeta reprodutibilidade de treino (o mesmo código com a mesma temporada pode dar outro resultado).
- **Regenerar nem sempre é possível.** A fonte é a mesma que se torna instável a partir de IPs de nuvem (tarefa 001, riscos). "Rodar de novo" é uma estratégia de recuperação mais fraca do que parece quando a origem bloqueia o ambiente futuro.
- A bronze deixa de ser um registro do que foi recebido e passa a ser "o último que recebemos".

Opções consideradas:

| Opção | Prós | Contras |
|---|---|---|
| 1. Sobrescrever puro (`games.parquet` fixo) | Mais simples; idempotência trivial; caminho determinístico | Perda total da versão anterior; sem auditoria |
| 2. Sobrescrever com guarda de regressão (recusar se o novo tiver menos linhas que o existente, liberável por flag explícita) | Barato (poucas linhas de lógica + testes); cobre o caso mais provável de degradação (resposta parcial); mantém o layout | Heurística: não detecta valores errados com a mesma contagem de linhas; temporada corrente cresce, então só pega encolhimento |
| 3. Manter uma cópia `.prev` (ou `.bak`) da versão anterior | Permite desfazer 1 passo | Dois arquivos por partição para gerenciar; nome precisa evitar o glob de leitura; guarda só 1 versão, a segunda execução ruim apaga a boa |
| 4. Snapshots imutáveis por execução (`run_id=.../`) mais ponteiro para o corrente | Auditoria completa; reprodutibilidade; rollback | Quebra a regra "nome determinístico" e o layout lido por Athena/Polars sem lógica extra de "qual é a corrente"; mais complexidade; vira small files; desproporcional hoje |
| 5. Versionamento do bucket S3 na migração | Histórico e rollback sem mudar o código; custo desprezível com ~30 objetos de KB; configurável com lifecycle (expirar versões antigas após N dias) | Só existe na AWS (não resolve a fase local); precisa lifecycle para o custo não crescer sem controle; recuperar versão exige procedimento |

**Decisão**: adotar a opção 2 agora (guarda de regressão, critério 22 da tarefa 001) e planejar a opção 5 na migração para S3. Rejeitar 3 e 4 por enquanto: 3 dá falsa segurança (uma versão só) e 4 complica o layout que acabamos de escolher para ganhar um recurso que o volume e a fase do projeto não exigem.

Consequência assumida, sem eufemismo: durante a fase local, **o projeto aceita o risco de perder uma versão boa por dado ruim com mesma contagem de linhas**. Isso é aceitável porque o volume é pequeno e a fonte é regenerável hoje, mas deixa de ser aceitável se a ingestão migrar para um ambiente onde a fonte bloqueia, ou se a bronze virar a única cópia de dados que a NBA corrigiu. Nesse caso, reabrir esta ADR e subir para a opção 4.

## Revisão

Reavaliar se: (d) a fonte passar a ser bloqueada no ambiente de execução (a perda de versão deixa de ser recuperável), ou a NBA publicar correções retroativas relevantes (subir para snapshots imutáveis), (a) entrar um dataset com volume por partição > ~128 MB ou com granularidade intradiária, (b) surgir necessidade de upsert por chave em escala (considerar Iceberg/Delta), ou (c) a migração para S3 revelar problema de listagem/consulta.
