# Instalação

## Requisitos

- Os mesmos do MONAN oficial, incluindo `datain/fixed` e `datain/WPS_GEOG`.
- Python 3 com `numpy` e `eccodes`, e o `cdo` para o ICON.
- Internet no nó onde roda o `2.pre_processing.bash`.

## Clone novo

```bash
cd /sua/area/de/trabalho
git clone https://github.com/phbazzo/MONAN-IFS-ICON.git scripts_CD-CT
cd scripts_CD-CT/scripts
./1.install_monan.bash https://github.com/monanadmin/MONAN-Model.git 2.0.0-rc 1.2.0
```

A pasta precisa se chamar `scripts_CD-CT`, e os scripts precisam rodar de dentro de `scripts_CD-CT/scripts`. Se
instalar outro branch do modelo, mude `MONAN_BRANCH` no `setenv.bash`.

Depois confira:

1. `setenv.bash`: `MODERUN`, `LBCINT`, `COMPILER`, `NVERTLEV` e `ZETA_LEVELS`.
2. `stools/setenv_<SCHEDULER>_<HOST>_<COMPILER>.bash`: módulos, filas, núcleos e *walltime*. Há arquivos para a JACI,
   a Egeon e um genérico. Em outra máquina, copie o mais parecido e inclua o *host* no `case` do `setenv.bash`.
3. `datain/fixed` e `datain/WPS_GEOG`: na JACI e na Egeon são copiados automaticamente; em outras máquinas, coloque-os
   antes.

### Malha nova (regional ou global)

1. Coloque `x1.<RES>.grid.nc` e `x1.<RES>.graph.info` em `datain/fixed/`.
2. No `3.run_model.bash`, inclua o `RES` com `CONFIG_DT` e `CONFIG_CONV_INTERVAL` (na malha de 3 km: `12.0` e
   `"00:10:00"`).
3. No `4.run_post.bash`, inclua a grade de saída (`NLAT`, `NLON`, `STARTLAT`, `ENDLAT`, `STARTLON`, `ENDLON`).
4. Fora da América do Sul, mude o `ICON_BOX` ([ICON](03-icon.md#recorte-icon_box)).

O `static.nc` é criado na primeira rodada. Rode uma vez antes de rodar várias em paralelo numa malha nova.

## Instalação existente

Troque a pasta `scripts/` pela deste repositório (guarde a sua) e refaça as entradas da sua malha no
`3.run_model.bash` e no `4.run_post.bash`. Ou leve só as partes novas para os seus scripts:
[portar para outra instalação](08-portar-para-outra-instalacao.md).

## Python e cdo

```bash
conda create -n monan_grib -c conda-forge python numpy python-eccodes cdo
```

Os scripts usam `ICON_PYTHON`, se definido; senão, o primeiro ambiente conda com `numpy` e `eccodes`. O `cdo` é o do
mesmo ambiente, ou o definido em `ICON_CDO`.

Na JACI, o `cdo` do módulo `cdo/2.4.2` falha com `CCE OpenMP fatal error`. Use o do conda.

Para ver qual Python será usado:

```bash
bash -c '. ./setenv.bash > /dev/null; find_python'
```

## Primeiro teste recomendado

```bash
L=$(date -u +%Y%m%d)00
./2.pre_processing.bash IFS <RES> ${L} 6 2>&1 | tee ~/pre_IFS_${L}.log
ls ../dataout/${L}/IFS/Pre/
grep -iE "error|crit|vertical grid" ../dataout/${L}/IFS/Pre/logs/log.init_atmosphere.0000.*.out
```

Com a grade L75, o log deve mostrar `Setting up vertical grid using levels from 'zeta_levels.L75.txt'`.
