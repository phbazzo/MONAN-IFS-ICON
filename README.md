# MONAN com ICON e IFS como condição inicial e de contorno

> **English summary.** MONAN workflow scripts (based on
> [`monanadmin/scripts_CD-CT`](https://github.com/monanadmin/scripts_CD-CT)) that add DWD ICON and ECMWF IFS
> open-data forecasts as initial and lateral boundary conditions (`EXP=ICON` / `EXP=IFS`). Data are downloaded and
> converted to WPS intermediate files without `ungrib`. Includes a 75-level vertical grid. Tested end to end with
> GFS, ICON and IFS on a 3 km regional mesh (MONAN-Model 2.0.0-rc). Documentation is in Portuguese.

Scripts do MONAN (`scripts_CD-CT`) com duas fontes novas de condição inicial (CI) e de contorno (CC):

| `EXP` | Fonte | Grade | Níveis verticais | Disponível por | Usa `ungrib` |
|---|---|---|---|---|---|
| `GFS` | NCEP | 0,25° | pressão | | sim |
| `ERA` | ERA5 | 0,25° | pressão | arquivo | sim |
| `ICON` | DWD | ~13 km, remapeada para 0,125° | ~74 do modelo (ou 18 de pressão) | ~24 h | não |
| `IFS` | ECMWF | 0,1° ou 0,25° | 14 de pressão | ~3 dias (AWS desde 2023) | não |

Os dados são baixados e convertidos pelos scripts. O `init_atmosphere`, o modelo e o pós são os do MONAN. O
repositório também inclui uma grade vertical de 75 níveis e grava cada fonte em `dataout/<LABELI>/<EXP>/`.

## Validação

Testado em 13/11/2026 com GFS, ICON e IFS: pré-processamento, modelo e pós, grade de 75 níveis, MONAN-Model
`2.0.0-rc`, malha regional de 3 km no Sul do Brasil, supercomputador JACI do INPE (PBS/Cray, Intel).

Ainda não testado: a cadeia completa com o IFS das 06/18 UTC (só o download foi testado), o ICON em níveis de
pressão e o modo global. A qualidade das previsões não foi avaliada.

## Uso

```bash
cd /sua/area/de/trabalho
git clone https://github.com/phbazzo/MONAN-IFS-ICON.git scripts_CD-CT    # a pasta precisa ter esse nome
cd scripts_CD-CT/scripts
./1.install_monan.bash https://github.com/monanadmin/MONAN-Model.git 2.0.0-rc 1.2.0
conda create -n monan_grib -c conda-forge python numpy python-eccodes cdo  # uma vez
```

Ajuste o `setenv.bash` e o `stools/setenv_*.bash` da sua máquina. Os scripts encontram o ambiente conda sem
precisar ativá-lo.

Rode no nó de login, porque o pré-processamento baixa os dados:

```bash
L=$(date -u +%Y%m%d)00
./2.pre_processing.bash ICON <RES> ${L} 48
./3.run_model.bash      ICON <RES> ${L} 48
./4.run_post.bash       ICON <RES> ${L} 48
```

As saídas ficam em `../dataout/${L}/ICON/`. Para o IFS, troque `ICON` por `IFS`.

## Avisos

1. O recorte padrão é a América do Sul (`ICON_BOX=-95,-25,-60,15`). Em outra região, defina `ICON_BOX` com folga
   em volta da malha.
2. O `setenv.bash` vem com `MODERUN=R`, 75 níveis e `COMPILER=intel`. Para os 55 níveis do MONAN oficial, use
   `NVERTLEV=55` e `ZETA_LEVELS=` vazio.
3. Malha nova precisa de uma entrada no `3.run_model.bash` e outra no `4.run_post.bash`.
4. O ICON fica disponível só por ~24 h. Para usar uma data, baixe no mesmo dia.
5. O download usa o nó de login. ICON de 48 h com LBC a cada 3 h ocupa ~22 GB; o IFS a 0,1°, ~0,2 GB por horário.
6. O IFS tem só 14 níveis de pressão, e o ICON em pressão vai só até 30 hPa. Por isso o ICON usa os níveis do modelo.
7. Para rodar a mesma fonte com outra configuração, use `RUN_TAG` (ex.: `RUN_TAG=L55`). Não rode duas vezes ao
   mesmo tempo com o mesmo `EXP` e `RUN_TAG`.
8. Cite as fontes dos dados: [DWD](https://www.dwd.de/EN/service/legal_notice/legal_notice_node.html) e
   [ECMWF](https://www.ecmwf.int/en/forecasts/datasets/open-data).

Erros e soluções: [solução de problemas](docs/07-avisos-e-solucao-de-problemas.md).

## Documentação

- [Visão geral](docs/01-visao-geral.md): como os dados chegam ao `init_atmosphere`
- [Instalação](docs/02-instalacao.md): requisitos, malha nova, instalação existente
- [ICON](docs/03-icon.md) e [IFS](docs/04-ifs.md): download, conversão, variáveis
- [Níveis verticais](docs/05-niveis-verticais.md): `NVERTLEV`, `ZETA_LEVELS`, grade L75
- [Configuração](docs/06-configuracao.md): todas as variáveis e exemplos de uso
- [Solução de problemas](docs/07-avisos-e-solucao-de-problemas.md): avisos e mensagens de erro
- [Portar para outra instalação](docs/08-portar-para-outra-instalacao.md): o que mudar em outro `scripts_CD-CT`

## Arquivos novos ou alterados

```
scripts/
├── setenv.bash                 variáveis (NVERTLEV, ZETA_LEVELS, RUN_TAG, ICON_PYTHON...) e funções
├── 2.pre_processing.bash       baixa e converte ICON/IFS
├── get_icon_dwd.bash           download do ICON
├── icon_levels.py              escolha dos níveis do ICON
├── make_degrib_ICON.bash       conversão do ICON (chama icon2wps.py)
├── icon2wps.py                 conversor do ICON
├── get_ifs_ecmwf.bash          download do IFS
├── make_degrib_IFS.bash        conversão do IFS (chama ifs2wps.py)
├── ifs2wps.py                  conversor do IFS
├── zeta_levels.py              gera grades verticais
└── namelists/zeta_levels.L75.txt
```

## Créditos

Scripts originais: equipe do MONAN/INPE ([`monanadmin/scripts_CD-CT`](https://github.com/monanadmin/scripts_CD-CT)).
ICON, IFS e grade L75: [@phbazzo](https://github.com/phbazzo). Dados: DWD (ICON) e ECMWF (IFS).
