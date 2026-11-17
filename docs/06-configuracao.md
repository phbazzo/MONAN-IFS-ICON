# Configuração

`MODERUN`, `LBCINT`, `NVERTLEV` e `ZETA_LEVELS` ficam no `setenv.bash`. As outras variáveis podem ir na frente do
comando:

```bash
ICON_BOX=-20,40,-40,10 ICON_NPROC=4 ./2.pre_processing.bash ICON <RES> 2026111300 24
```

Use os mesmos valores de `RUN_TAG`, `NVERTLEV` e `LBCINT` nas etapas 2, 3 e 4.

## Variáveis

| Variável | Padrão | Uso |
|---|---|---|
| `MODERUN` | `R` | `R` regional, `G` global |
| `LBCINT` | `10800` | intervalo das LBCs (s) |
| `NVERTLEV` | `75` | número de níveis |
| `ZETA_LEVELS` | `zeta_levels.L75.txt` | grade vertical; vazio = TC |
| `RUN_TAG` | vazio | grava em `dataout/<LABELI>/<EXP>_<RUN_TAG>` |
| `ICON_PYTHON` | procura | Python da conversão |
| `ICON_CDO` | o do ambiente | `cdo` |
| `ICON_VCOORD` | `model` | `model` ou `pressure` |
| `ICON_ZFULL` | `16000` | altura com todos os níveis do ICON |
| `ICON_THIN` | `2` | 1 nível a cada N acima de `ICON_ZFULL` |
| `ICON_ZTOP` | `config_ztop` | topo para escolher os níveis |
| `ICON_BOX` | `-95,-25,-60,15` | recorte |
| `ICON_NPROC` | `32` / `8` | processos no download / na conversão |
| `IFS_RESOL` | `0p1` | `0p1`, `0p25`, `0p4-beta` |
| `IFS_SOURCE` | `ecmwf` | `ecmwf` ou `aws` |
| `IFS_NPROC` | `8` | downloads em paralelo |
| `IFS_BOX` | `ICON_BOX` | recorte do IFS |

## Exemplos

### Outra região

Siga os passos de [malha nova](02-instalacao.md#malha-nova-regional-ou-global) e defina `ICON_BOX`. Malhas que cruzam
180° de longitude não são suportadas.

<a id="comparar-fontes"></a>
### Comparar fontes na mesma data

```bash
L=2026111300; R=<RES>
for EXP in ICON IFS GFS; do
   ./2.pre_processing.bash ${EXP} ${R} ${L} 48 && \
   ./3.run_model.bash      ${EXP} ${R} ${L} 48 && \
   ./4.run_post.bash       ${EXP} ${R} ${L} 48
done
ls ../dataout/${L}/          # GFS  ICON  IFS
```

### Mesma fonte, outra configuração

```bash
export RUN_TAG=L55          # com NVERTLEV=55 e ZETA_LEVELS= no setenv.bash
./2.pre_processing.bash ICON <RES> 2026111300 48
./3.run_model.bash      ICON <RES> 2026111300 48
./4.run_post.bash       ICON <RES> 2026111300 48
```

O resultado fica em `dataout/2026111300/ICON_L55/`. Rodadas com `RUN_TAG` diferentes podem rodar em paralelo.

### Datas antigas

- IFS: `IFS_SOURCE=aws` (desde 2023); antes de fev/2024, também `IFS_RESOL=0p4-beta`.
- ICON: não há arquivo público. Baixe no dia (`./get_icon_dwd.bash LABELI FCST`). Depois o pré-processamento pode ser
  refeito sem internet.

### Download diário do ICON

```bash
0 5 * * * bash -lc 'cd /caminho/scripts_CD-CT/scripts && ./get_icon_dwd.bash $(date -u +\%Y\%m\%d)00 48' >> $HOME/icon_cron.log 2>&1
```

Cada rodada de 48 h ocupa ~22 GB.

### Menos disco

- `ICON_VCOORD=pressure`: ~4× menos, com perda de resolução vertical.
- `ICON_THIN=3` ou `ICON_ZFULL=12000`: menos níveis no alto.
- `IFS_RESOL=0p25`: ~4× menos que `0p1`.
- `LBCINT=21600`: metade dos horários.
- Apague `datain/ICON/<LABELI>` depois da rodada.

### Modo global (não testado)

Use `MODERUN=G`. Só a hora inicial é baixada. O ICON global precisa de ~10 GB de RAM na conversão.

### Convecção explícita

Use o ICON nos níveis do modelo e a grade L75. `LBCINT=3600` só funciona com o ICON. Descarte as primeiras horas na
avaliação: nenhuma fonte traz nuvens e chuva na condição inicial.
