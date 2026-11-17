# Portar para outra instalação

Para levar o ICON e o IFS a outro `scripts_CD-CT` sem trocar a pasta `scripts/`. Compare os arquivos com
`diff -u seu/arquivo este/arquivo` para ver as linhas exatas.

## 1. Copiar os arquivos novos

```
get_icon_dwd.bash   make_degrib_ICON.bash   icon2wps.py   icon_levels.py
get_ifs_ecmwf.bash  make_degrib_IFS.bash    ifs2wps.py
zeta_levels.py      namelists/zeta_levels.L75.txt     (só para a grade vertical)
```

```bash
chmod +x scripts/*.bash scripts/*.py
```

## 2. `setenv.bash`

Incluir:

```bash
export NVERTLEV=75                       # ou 55
export ZETA_LEVELS=zeta_levels.L75.txt   # ou vazio
export RUN_TAG=${RUN_TAG:-}
export ICON_PYTHON=${ICON_PYTHON:-}
export ICON_CDO=${ICON_CDO:-}
```

E copiar as funções `find_python` e `run_name`.

## 3. `2.pre_processing.bash`

1. Definir `RUNNAME=$(run_name ${EXP})` e `OUTRUN=${DATAOUT}/${YYYYMMDDHHi}/${RUNNAME}`.
2. Antes da cópia de `datain/fixed`, para ICON/IFS: `export ICON_PYTHON=$(find_python)` e chamar
   `./get_icon_dwd.bash` ou `./get_ifs_ecmwf.bash`.
3. Aceitar `ICON` e `IFS` nas etapas de static, conversão e init.
4. Na conversão, chamar `./make_degrib_ICON.bash` ou `./make_degrib_IFS.bash`.

## 4. Namelists

| Arquivo | Linha |
|---|---|
| `namelist.init_atmosphere.TEMPLATE` e `.LBCS` | `config_nfglevels = 80` |
| `namelist.init_atmosphere.TEMPLATE` e `.LBCS` | `config_nvertlevels = #NVERTLEV#` |
| `namelist.init_atmosphere.TEMPLATE` | `config_specified_zeta_levels = '#ZETA_LEVELS#'` |

## 5. `make_initatmos.bash` e `make_lbcs.bash`

- Usar `OUTRUN` e `run.${YYYYMMDDHHi}.${RUNNAME}`.
- No `sed` do namelist: `s,#NVERTLEV#,${NVERTLEV},g;s,#ZETA_LEVELS#,${ZETA_LEVELS},g`.
- No `make_initatmos.bash`, copiar o bloco que confere o arquivo de alturas.

## 6. `3.run_model.bash`

```bash
if [[ ${EXP} != "ICON" && ${EXP} != "IFS" ]]; then files_needed+=("${DATAIN}/fixed/Vtable.${EXP}"); fi
if [[ ${EXP} != "ICON" && ${EXP} != "IFS" ]]; then cp -f ${DATAIN}/fixed/Vtable.${EXP} ${DIRRUN}; fi
```

- Aceitar `ICON` e `IFS` na geração do `namelist.atmosphere`.
- `NLEV=${NVERTLEV}` no lugar de `55`.
- Usar `OUTRUN` e `RUNNAME`.

## 7. `4.run_post.bash`

`N_MODEL_LEV=${NVERTLEV}` no lugar de `55`, e `OUTRUN`/`RUNNAME`.

## 8. Outros scripts

`make_static.bash`, `make_degrib_GFS.bash`, `make_degrib_ERA5.bash` e `make_template.bash` também usam `RUNNAME` e
`OUTRUN`. Se preferir manter `dataout/<LABELI>/` sem subpasta por fonte, ajuste `RUNNAME`, `OUTRUN` e `DIRRUN` nos
scripts novos.

Depois, faça um [teste curto](02-instalacao.md#primeiro-teste-recomendado) com cada fonte.
