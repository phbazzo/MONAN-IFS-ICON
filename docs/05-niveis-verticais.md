# Níveis verticais

Vale para qualquer fonte. O MONAN oficial usa 55 níveis (grade TC do MPAS). Aqui a grade é definida no `setenv.bash`:

| Variável | Padrão | Efeito |
|---|---|---|
| `NVERTLEV` | `75` | número de níveis do init, das LBCs e do nome dos arquivos |
| `ZETA_LEVELS` | `zeta_levels.L75.txt` | arquivo em `namelists/` com as alturas; vazio = grade TC |

Grade oficial:

```bash
export NVERTLEV=55
export ZETA_LEVELS=
```

O `make_initatmos.bash` confere se o arquivo tem `NVERTLEV + 1` valores e se o último é igual ao `config_ztop`. No
log do init deve aparecer `Setting up vertical grid using levels from 'zeta_levels.L75.txt'`.

## Grade L75

Para 3 km com convecção explícita (`config_dt = 12 s`):

- 75 níveis até 30 km;
- primeiro nível a 10 m;
- 25 níveis abaixo de 2 km (a grade TC com 75 níveis tem 19);
- 480 m de espessura entre 2 e 12 km;
- 10 níveis acima de 22 km (`config_zd`).

## Gerar outra grade

```bash
python zeta_levels.py --nlev 75 --ztop 30000 --dzbot 20 --r1 1.10 --dzmid 480 --ztrans 12000 \
       > namelists/zeta_levels.L75.txt
```

| Opção | Significado |
|---|---|
| `--dzbot` | espessura da primeira camada |
| `--r1` | aumento de cada camada na camada limite |
| `--dzmid` | espessura constante na troposfera |
| `--ztrans` | altura onde a espessura volta a aumentar |

Depois ajuste `NVERTLEV` e `ZETA_LEVELS`.

## Ao mudar a grade

1. Refaça o pré-processamento (`init.nc` e LBCs dependem do número de níveis).
2. Confira o `config_dt` e o log do modelo nas primeiras horas.
3. Mantenha vários níveis acima de `config_zd`.
4. 75 níveis custam ~36 % mais que 55: aumente o `MODEL_walltime`.
5. Os arquivos passam a terminar em `L75.nc`.
6. Se mudar o `config_ztop`, gere as alturas com o mesmo topo e apague `model_levels.txt` e `download_ok` do ICON.
