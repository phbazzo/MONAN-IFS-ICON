# ICON (DWD)

## Dados

- Fonte: `https://opendata.dwd.de/weather/nwp/icon/grib/`, grade de ~13 km, 120 níveis.
- Rodadas: 00, 06, 12 e 18 UTC. Saída horária até +78 h e a cada 3 h depois. Vai até +180 h (00/12 UTC) ou +120 h
  (06/18 UTC).
- Cada rodada fica disponível por ~24 h.

## Download

O `2.pre_processing.bash` chama o `get_icon_dwd.bash`. Para só baixar: `./get_icon_dwd.bash LABELI FCST`.

| Dados | Variáveis | Horários |
|---|---|---|
| Fixos | `HSURF`, `FR_LAND` | uma vez |
| Atmosfera, níveis do modelo | `T`, `U`, `V`, `QV`, `P` | todos |
| Atmosfera, pressão | `T`, `U`, `V`, `RELHUM`, `FI` | todos |
| Superfície | `PS`, `PMSL`, `T_2M`, `TD_2M`, `U_10M`, `V_10M`, `T_G` | todos |
| Neve, gelo e solo | `FR_ICE`, `W_SNOW`, `H_SNOW`, `T_SO`, `W_SO` | só +0 h |

- Os horários vão de 0 a `FCST`, a cada `LBCINT`. `LBCINT` precisa ser múltiplo de 1 h (de 3 h depois de +78 h).
- Na primeira vez, o script também baixa os pesos do remapeamento e as alturas dos níveis (`HHL`).
- Se o download parar, rode de novo para continuar. No fim, o script grava `download_ok` e não consulta mais o DWD.
- Tamanho: ~1,3 GB por horário nos níveis do modelo (~22 GB para 48 h com LBC a cada 3 h).

## Níveis (`ICON_VCOORD`)

| | `model` (padrão) | `pressure` |
|---|---|---|
| Níveis | ~74 | 18 |
| Topo | acima do topo do MONAN | 30 hPa (~24 km) |
| Disco | ~4× maior | menor |

Use `model`. Com `pressure`, o init extrapola acima de ~24 km.

O `icon_levels.py` escolhe os níveis:

1. todos até `ICON_ZFULL` (16 000 m);
2. acima disso, um a cada `ICON_THIN` (2);
3. um nível acima do topo do MONAN (`config_ztop`).

Com topo de 30 km, são 74 níveis, salvos em `datain/ICON/<LABELI>/model_levels.txt`. O limite é 79 níveis
(`config_nfglevels = 80`).

Se mudar `config_ztop`, `ZETA_LEVELS`, `ICON_ZFULL` ou `ICON_THIN`, apague `model_levels.txt` e `download_ok`.

## Conversão

O `icon2wps.py`:

1. descomprime e remapeia para lat-lon 0,125° com o `cdo` e os pesos do DWD;
2. recorta a região (`ICON_BOX`);
3. calcula umidade específica, umidade relativa e altura geopotencial;
4. reagrupa o solo nas 4 camadas do GFS;
5. grava `dataout/<LABELI>/ICON/Pre/ICON:YYYY-MM-DD_HH`.

Log: `dataout/<LABELI>/ICON/Pre/logs/icon2wps.*.log`.

## Recorte (`ICON_BOX`)

Padrão no regional: `-95,-25,-60,15` (lon1,lon2,lat1,lat2), a América do Sul. No global, usa o globo inteiro.

Em outra região, defina uma caixa alguns graus maior que a malha, com longitudes entre −180 e 180 e `lon1 < lon2`.

## Variáveis

| Variável | Padrão | Uso |
|---|---|---|
| `ICON_PYTHON` | procura | Python com `numpy` e `eccodes` |
| `ICON_CDO` | o do ambiente | `cdo` |
| `ICON_VCOORD` | `model` | `model` ou `pressure` |
| `ICON_ZFULL` | `16000` | altura com todos os níveis |
| `ICON_THIN` | `2` | 1 nível a cada N acima de `ICON_ZFULL` |
| `ICON_ZTOP` | `config_ztop` | topo para escolher os níveis |
| `ICON_BOX` | `-95,-25,-60,15` | recorte |
| `ICON_NPROC` | `32` / `8` | processos no download / na conversão |

Exemplo: `ICON_BOX=-20,40,-40,10 ./2.pre_processing.bash ICON ...`.
