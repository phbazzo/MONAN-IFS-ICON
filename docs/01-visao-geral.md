# Visão geral

O `init_atmosphere` lê arquivos intermediários do WPS, não GRIB. No fluxo oficial, o `ungrib.exe` gera esses
arquivos a partir do GFS. Para o ICON e o IFS, scripts em Python geram o mesmo formato:

```
GFS:   GRIB2 ──ungrib.exe──────────────────────────▶ Pre/GFS:YYYY-MM-DD_HH
ICON:  DWD   ──get_icon_dwd.bash──▶ make_degrib_ICON.bash (icon2wps.py) ──▶ Pre/ICON:YYYY-MM-DD_HH
IFS:   ECMWF ──get_ifs_ecmwf.bash─▶ make_degrib_IFS.bash (ifs2wps.py) ───▶ Pre/IFS:YYYY-MM-DD_HH

Pre/<EXP>:... ──make_initatmos.bash──▶ init.nc ──make_lbcs.bash──▶ lbc.*.nc ──▶ 3.run_model ──▶ 4.run_post
```

O ICON não pode usar o `ungrib` porque a grade é icosaédrica e os níveis são de altura. O IFS poderia, mas faltariam
campos como umidade específica e solo nas camadas do GFS.

O namelist usa `config_met_prefix = '#EXP#'`, então o init lê `ICON:...` ou `IFS:...` sem outra mudança.

## Pastas

```
scripts_CD-CT/
├── datain/
│   ├── fixed/            malhas, static, tabelas; icon_cdo/ e icon_hhl/ (ICON)
│   ├── ICON/<LABELI>/    dados baixados do DWD
│   └── IFS/<LABELI>/     dados baixados do ECMWF
├── dataout/<LABELI>/<RUNNAME>/      RUNNAME = EXP ou EXP_RUN_TAG
│   ├── Pre/              intermediários, init.nc, lbc.*.nc, logs/
│   ├── Model/            saídas do modelo
│   └── Post/             saídas em lat-lon
└── run.<LABELI>.<RUNNAME>/          pasta temporária
```

## Scripts

| Script | Onde roda | Função |
|---|---|---|
| `setenv.bash` | todos | variáveis e funções `find_python` e `run_name` |
| `2.pre_processing.bash` | login | baixa ICON/IFS e depois roda static, conversão, init e LBC |
| `get_icon_dwd.bash` | login | baixa o ICON |
| `icon_levels.py` | login | escolhe os níveis do ICON |
| `make_degrib_ICON.bash`, `icon2wps.py` | login | remapeia o ICON para lat-lon e grava o intermediário |
| `get_ifs_ecmwf.bash` | login | baixa só os campos necessários do IFS |
| `make_degrib_IFS.bash`, `ifs2wps.py` | login | recorta o IFS e grava o intermediário |
| `make_initatmos.bash`, `make_lbcs.bash` | fila | aplicam a grade vertical e rodam o init |
| `3.run_model.bash`, `4.run_post.bash` | fila | modelo e pós; ICON/IFS não precisam de `Vtable` |
| `zeta_levels.py` | qualquer | gera grades verticais |

## Campos gravados

| Campo WPS | ICON (níveis do modelo) | ICON (pressão) | IFS |
|---|---|---|---|
| `TT`, `UU`, `VV` | `T`, `U`, `V` | `T`, `U`, `V` | `t`, `u`, `v` |
| `SPECHUMD` | `QV` | de `RELHUM` | de `r` |
| `RH` | de `QV`, `P`, `T` | `RELHUM` | `r` |
| `GHT` | de `HHL` | `FI / g` | `gh` |
| `PRESSURE` | `P` | | |
| `PSFC`, `PMSL` | `PS`, `PMSL` | idem | `sp`, `msl` |
| 2 m | `T_2M`, `TD_2M` | idem | `2t`, `2d` |
| 10 m | `U_10M`, `V_10M` | idem | `10u`, `10v` |
| `SKINTEMP` | `T_G` | idem | `skt` |
| `SOILHGT` | `HSURF` | idem | `z / g` |
| `LANDSEA` | `FR_LAND ≥ 0,5` | idem | `lsm ≥ 0,5` |
| `SEAICE`, `SNOW`, `SNOWH` (só CI) | `FR_ICE`, `W_SNOW`, `H_SNOW` | idem | `sithick > 0`, `sd·1000`, `sd·1000/rsn` |
| solo (só CI) | `W_SO`, `T_SO` | idem | `vsw`, `sot` |

O solo é reagrupado nas 4 camadas do GFS: 0–10, 10–40, 40–100 e 100–200 cm.
