# IFS (ECMWF)

## Dados

- `IFS_SOURCE=ecmwf` (padrão): `https://data.ecmwf.int/forecasts/`, últimos ~3 dias.
- `IFS_SOURCE=aws`: `https://ecmwf-forecasts.s3.eu-central-1.amazonaws.com`, desde 2023.
- `IFS_RESOL`: `0p1` (padrão), `0p25` ou `0p4-beta` (antes de fev/2024).
- O `0p1` é publicado ~2 h depois do `0p25`. Se precisar antes, use `0p25`.
- Rodadas 00/12 UTC até +360 h; 06/18 UTC até +144 h. Saída a cada 3 h até +144 h e a cada 6 h depois.
- O script testa os *streams* `oper` e `scda` (este só em datas antigas).

## Download

O `get_ifs_ecmwf.bash` confere o horário da rodada e o `LBCINT` antes de baixar. Depois baixa só os campos
necessários:

| Arquivo | Campos | Horários |
|---|---|---|
| `ifs_pl.FFF.grib2` | `t`, `u`, `v`, `r`, `gh` em 14 níveis (1000 a 10 hPa) | todos |
| `ifs_sfc.FFF.grib2` | `sp`, `msl`, `2t`, `2d`, `10u`, `10v`, `skt` | todos |
| `ifs_sfc0.grib2` | `z`, `lsm`, `sd`, `rsn`, `sithick` | +0 h |
| `ifs_sol.grib2` | `sot`, `vsw` | +0 h |

- Tamanho: ~0,2 GB por horário a 0,1°.
- Arquivos já baixados não são baixados de novo.
- O download precisa só de `python3`; a conversão precisa de `numpy` e `eccodes`.

## Conversão

O `ifs2wps.py` recorta a região (`IFS_BOX`), calcula umidade específica, reagrupa o solo nas camadas do GFS e grava
`dataout/<LABELI>/IFS/Pre/IFS:YYYY-MM-DD_HH`. O gelo marinho é 1 onde `sithick > 0`. Log:
`dataout/<LABELI>/IFS/Pre/logs/ifs2wps.*.log`.

## Limitações

- 14 níveis de pressão, só 3 abaixo de 700 hPa: a camada limite inicial tem pouca resolução.
- Topo em 10 hPa (~31 km), pouco acima do topo do MONAN.
- Gelo marinho só 0 ou 1.

## Variáveis

| Variável | Padrão | Uso |
|---|---|---|
| `IFS_RESOL` | `0p1` | resolução |
| `IFS_SOURCE` | `ecmwf` | `ecmwf` ou `aws` |
| `IFS_NPROC` | `8` | downloads em paralelo |
| `IFS_BOX` | `ICON_BOX` | recorte |

Exemplo, data antiga a 0,25°:

```bash
IFS_SOURCE=aws IFS_RESOL=0p25 ./2.pre_processing.bash IFS <RES> 2026111000 48
```
