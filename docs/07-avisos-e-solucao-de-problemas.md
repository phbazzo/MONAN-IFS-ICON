# Avisos e solução de problemas

## Avisos

- ICON disponível por ~24 h; IFS por ~3 dias (depois, `IFS_SOURCE=aws`).
- Rodadas saem algumas horas depois do horário nominal. Se faltar arquivo, rode de novo.
- Espaço: ~1,3 GB por horário (ICON) ou ~0,2 GB (IFS a 0,1°).
- O recorte padrão é a América do Sul. Em outra região, mude o `ICON_BOX`.
- O `2.pre_processing.bash` precisa de internet: rode no nó de login, não como job.
- Use os mesmos `RUN_TAG`, `NVERTLEV` e `LBCINT` nas etapas 2, 3 e 4.
- Não rode duas vezes ao mesmo tempo com o mesmo `EXP` e `RUN_TAG`.
- Mudou a grade vertical ou os níveis do ICON? Apague `model_levels.txt` e `download_ok` e refaça o pré-processamento.
- O solo vem de outro modelo; o Noah-MP leva algumas horas para se ajustar.
- Antes de usar em trabalho científico, compare com uma rodada GFS da mesma data.

## Verificação

```bash
L=2026111300; P=../dataout/${L}/ICON/Pre
tail -40 ${P}/logs/icon2wps.*.log
grep -iE "levels|vertical grid|error|crit" ${P}/logs/log.init_atmosphere.0000.*.out | head -40
grep -E "nvertlevels|nfglevels|zeta|met_prefix" ${P}/logs/namelist.init_atmosphere
ncdump -h ${P}/x1.*.init.nc | grep -E "nVertLevels =|nCells ="
```

## Mensagens de erro

| Mensagem | Causa | Solução |
|---|---|---|
| `No Python with numpy + eccodes found` | sem ambiente com `eccodes` | criar o ambiente conda ou definir `ICON_PYTHON` |
| `CCE OpenMP fatal error: omp_set_num_threads attempted from non-OpenMP thread` | `cdo` do módulo da Cray | usar o `cdo` do conda ou `ICON_CDO` |
| `ICON run ... not found at https://opendata.dwd.de/...` | rodada antiga ou ainda não publicada | usar outra rodada ou esperar |
| `N files missing ... Run again to resume` | publicação incompleta ou horário inexistente | rodar de novo; conferir `LBCINT` e `FCST` |
| `Too many levels for config_nfglevels = 80` | mais de 79 níveis do ICON | aumentar `ICON_THIN` |
| `LABELI must be a 00, 06, 12 or 18 UTC run` | horário inválido | usar 00, 06, 12 ou 18 |
| `IFS: LBCINT ... must be a multiple of 10800 s` | `LBCINT` incompatível | múltiplo de 3 h |
| `6-hourly output after +144 h` / `06/18 UTC runs go only up to +144 h` | `FCST` longo demais | reduzir `FCST` ou ajustar `LBCINT` |
| `IFS run ... is published at 0p25 but not yet at 0p1` | `0p1` ainda não publicado | esperar ou `IFS_RESOL=0p25` |
| `IFS run ... not found at ...` | rodada fora do portal | `IFS_SOURCE=aws` |
| `Step +N h not found` | passo não publicado | esperar ou reduzir `FCST` |
| `fields missing in the ECMWF files: [...]` | mudança nos dados do ECMWF | abrir uma *issue* |
| `Recorte ... vazio ou cruzando a borda da grade do IFS` | `ICON_BOX` inválido | `lon1,lon2,lat1,lat2` com `lon1 < lon2` |
| `... has N lines / N values; expected NVERTLEV+1` | `NVERTLEV` errado | `NVERTLEV` = linhas − 1 |
| `Top of ... differs from config_ztop` | topo diferente | gerar as alturas com o mesmo `config_ztop` |
| `RUN_TAG must contain only letters, digits...` | caractere inválido | usar letras, dígitos, `_`, `.`, `-` |
| `Simulation parameters for resolution/mesh ... have not been set` | malha sem entrada no `3.run_model.bash` | incluir `CONFIG_DT` e `CONFIG_CONV_INTERVAL` |
| `Convert_MPAS parameters for resolution/mesh ... have not been set` | malha sem entrada no `4.run_post.bash` | incluir a grade de saída |
| `u10`, `v10`, `t2m` e `q2` absurdos (~ -1e30) só em +0 h (ICON/IFS) | erro do `init_atmosphere` 2.0.0-rc: na interpolação desses campos para as células, corrige a longitude só de um lado, e o recorte do ICON/IFS (longitude inicial negativa, ex.: -95) não cobre o `lonCell` da malha (0 a 360) | `cd scripts && ./patch_monan.bash init` (corrige o fonte e recompila só o `init_atmosphere`); depois refazer o `2.pre_processing.bash` e o modelo |
| Pós do ICON com `Time:units = "hours since _202-61-11 90:.0:.0"`; GrADS/CDO não abrem ou dão a data errada | o `convert_mpas` lê a data do nome do arquivo em posições fixas, que só valem para `EXP` de 3 letras | refazer o `4.run_post.bash` atual (passa ao `convert_mpas` um link `diag.AAAA-MM-DD_hh.mm.ss.nc`) |
| `.ctl` do pós vazio ou com `tdef` errado em rodada L75 | o `make_template.bash` procurava arquivos `L55` | refazer o `4.run_post.bash` atual |
| `ECCODES ERROR : pack_bytes: Wrong size (20) for section2Padding` | arquivos do DWD | pode ignorar |
| `bunzip2: ... trailing garbage after EOF ignored` | arquivos do DWD | pode ignorar |
