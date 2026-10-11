# Mentoria - memória do estagiário

Última atualização: 2026-10-11 (review do PR #2)

## Para estudar

| Tema | Motivo | Fonte |
|---|---|---|
| Higiene de notebooks no Git (outputs, metadados) | PR #2 trouxe diff ruidoso em `first.ipynb` (execution_count, kernelspec, output de erro) | nbstripout: https://github.com/kynan/nbstripout (remove outputs e metadados do notebook antes de versionar, via filtro Git ou pre-commit) |
| Ignorar vs deixar de rastrear no Git | `data/` está no `.gitignore`, mas os parquets de players/teams já estão rastreados; critério 19 da tarefa 001 | gitignore: https://git-scm.com/docs/gitignore (arquivos já rastreados não são afetados por padrões de ignore; ver `git rm --cached`) |
| Escopo e descrição de PR (uma mudança, com evidência) | PR #2 sem descrição, misturando tooling, docs e notebook | (sem fonte aberta ainda) |
| Pacote instalável em modo editável / ambiente do kernel | `ModuleNotFoundError: No module named 'src'` no notebook | (sem fonte aberta ainda) |

## Em andamento

- Tarefa 001 (bronze de games): entrega 1 (núcleo puro + testes) ainda não iniciada. Temas centrais: idempotência por partição, escrita atômica, retry/backoff, testes sem rede.

## Dominado

(nada registrado ainda)

## Padrões de erro recorrentes

- PR sem descrição e com mudanças não relacionadas misturadas (1a ocorrência, PR #2). Se repetir, sobe para BLOQUEANTE recorrente.
- Ruído de notebook versionado com output (1a ocorrência, PR #2).
