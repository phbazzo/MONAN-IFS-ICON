#!/bin/bash
umask 022
#-----------------------------------------------------------------------------#
# !SCRIPT: get_icon_dwd
#
# !DESCRIPTION:
#     Baixa do DWD opendata o ICON global (malha icosaedrica, GRIB2) usado com
#     EXP=ICON, e os pesos de remapeamento do CDO (so na primeira vez).
#
#        o ${DATAIN}/ICON/YYYYMMDDHH/*.grib2.bz2
#        o ${DATAIN}/fixed/icon_cdo/{target_grid.txt,weights.nc}
#
#     O DWD mantem so as rodadas das ultimas ~24 h (00, 06, 12 e 18 UTC).
#     Solo, neve e gelo marinho sao baixados so na hora inicial.
#
#     ICON_VCOORD=model (padrao): atmosfera nos niveis do modelo do ICON.
#        Os niveis sao escolhidos por icon_levels.py a partir do HHL
#        (guardado em ${DATAIN}/fixed/icon_hhl) e salvos em model_levels.txt:
#        ICON_ZFULL (16000 m: todos os niveis nativos ate a tropopausa, ~75
#        niveis, para nao ficar mais grosso que a grade L75 do MONAN),
#        ICON_THIN (2) e ICON_ZTOP (padrao: config_ztop
#        do namelist.init_atmosphere.TEMPLATE). Vai so UM nivel acima do topo.
#        Ao mudar algum deles, apague o model_levels.txt da rodada.
#
#     Rodar de novo e seguro: arquivos completos nao sao baixados outra vez
#     (wget -c) e, depois de um download completo (marcador download_ok), o
#     DWD nem e consultado.
#     ICON_VCOORD=pressure: os 18 niveis de pressao do opendata.
#-----------------------------------------------------------------------------#

if [ $# -ne 2 ]
then
   echo ""
   echo "Instructions: execute the command below"
   echo ""
   echo "${0} LABELI FCST"
   echo ""
   echo "LABELI      :: ICON run (YYYYMMDDHH), one of the last ~24 h, e.g., 2026110500"
   echo "FCST        :: Forecast length in hours (e.g., 24, 36, 48, etc.)"
   echo ""
   exit
fi

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash

# Standart directories variables:---------------------------------------
DIRHOMES=${DIR_SCRIPTS}/scripts_CD-CT;  mkdir -p ${DIRHOMES}
DIRHOMED=${DIR_DADOS}/scripts_CD-CT;    mkdir -p ${DIRHOMED}
SCRIPTS=${DIRHOMES}/scripts;            mkdir -p ${SCRIPTS}
DATAIN=${DIRHOMED}/datain;              mkdir -p ${DATAIN}
#----------------------------------------------------------------------

# Input variables:--------------------------------------
YYYYMMDDHHi=${1}; #YYYYMMDDHHi=2026110500
FCST=${2};        #FCST=24
#-------------------------------------------------------

# Local variables--------------------------------------
BASEURL=https://opendata.dwd.de/weather/nwp/icon/grib/${YYYYMMDDHHi:8:2}
OUT=${DATAIN}/ICON/${YYYYMMDDHHi};       mkdir -p ${OUT}
ICONCDO=${DATAIN}/fixed/icon_cdo
HHLDIR=${DATAIN}/fixed/icon_hhl
NPROC=${ICON_NPROC:-32}
VCOORD=${ICON_VCOORD:-model}
PYTHON=$(find_python) || exit 1   # numpy + eccodes (ICON_PYTHON ou ambiente conda; ver setenv.bash)
if [[ $MODERUN == "R" ]]; then dt=$((LBCINT / 3600)); else FCST=0; dt=1; fi

# pasta no DWD:variavel
PL="t:T u:U v:V relhum:RELHUM fi:FI"
ML="t:T u:U v:V qv:QV p:P"
SL="ps:PS pmsl:PMSL t_2m:T_2M td_2m:TD_2M u_10m:U_10M v_10m:V_10M t_g:T_G"
SL0="fr_ice:FR_ICE w_snow:W_SNOW h_snow:H_SNOW"
SOIL0="t_so:T_SO w_so:W_SO"
TI="hsurf:HSURF fr_land:FR_LAND"
#-------------------------------------------------------


# Rodada ja baixada por completo? O marcador download_ok (gravado no fim deste script) guarda
# "FCST DT VCOORD". Se cobre o pedido (mesmo DT e VCOORD, FCST >= o pedido) e os niveis escolhidos
# continuam la, nao consulta o DWD: o pre-processamento pode ser refeito depois que a rodada saiu do
# opendata (~24 h). Para forcar um novo download, apague ${OUT}/download_ok.
if [ -s ${OUT}/download_ok ]
then
   read mfcst mdt mvcoord < ${OUT}/download_ok
   if [[ ${mdt} == ${dt} && ${mvcoord} == ${VCOORD} && ${mfcst} -ge ${FCST} ]] && \
      [[ ${VCOORD} != "model" || -s ${OUT}/model_levels.txt ]]
   then
      echo -e "${GREEN}==>${NC} ICON ${YYYYMMDDHHi} (+${mfcst} h, ${VCOORD} levels) already downloaded in ${OUT}. Skipping download.\n"
      exit 0
   fi
fi


# Pesos de remapeamento do CDO (ICON global R03B07 -> lat-lon 0.125), uma vez:
if [ ! -s ${ICONCDO}/target_grid.txt ] || [ ! -s ${ICONCDO}/weights.nc ]
then
   echo -e "${GREEN}==>${NC} Downloading CDO remapping weights from DWD...\n"
   mkdir -p ${ICONCDO}
   cd ${ICONCDO}
   wget -c https://opendata.dwd.de/weather/lib/cdo/ICON_GLOBAL2WORLD_0125_EASY.tar.bz2 || exit 1
   tar -xjf ICON_GLOBAL2WORLD_0125_EASY.tar.bz2 || exit 1
   grid=$(find ${ICONCDO} -type f -name 'target_grid*.txt' | head -1)
   weights=$(find ${ICONCDO} -type f -name 'weights*.nc' | head -1)
   if [ -z "${grid}" ] || [ -z "${weights}" ]
   then
      echo -e "${RED}==>${NC} target_grid*.txt or weights*.nc not found in the tarball:"
      find ${ICONCDO} -type f
      exit 1
   fi
   ln -sf ${grid} target_grid.txt
   ln -sf ${weights} weights.nc
   rm -f ICON_GLOBAL2WORLD_0125_EASY.tar.bz2
fi


# Lista de arquivos:----------------------------------------------------
# Campos com varios niveis: nomes tirados da listagem da pasta no DWD
listing () {
   wget -qO- ${BASEURL}/${1}/ | grep -o "icon_global_icosahedral_${2}_${YYYYMMDDHHi}_[0-9]*_[0-9]*_${3}\.grib2\.bz2" | sort -u
}

if ! wget -qO- ${BASEURL}/ps/ | grep -q "single-level_${YYYYMMDDHHi}_000_PS"
then
   echo -e "${RED}==>${NC} ICON run ${YYYYMMDDHHi} not found at ${BASEURL}"
   echo -e "${RED}==>${NC} DWD opendata keeps only the last ~24 h of runs."
   exit 1
fi

if [[ ${VCOORD} == "model" ]]
then
   # HHL (alturas das meias-camadas 1 a 121), uma vez: nao muda entre rodadas
   if [ $(ls ${HHLDIR}/*_HHL.grib2.bz2 2>/dev/null | wc -l) -lt 121 ]
   then
      echo -e "${GREEN}==>${NC} Downloading ICON HHL (model level heights) to ${HHLDIR}...\n"
      mkdir -p ${HHLDIR}
      for k in $(seq 1 121); do
         echo "${BASEURL}/hhl/icon_global_icosahedral_time-invariant_${YYYYMMDDHHi}_${k}_HHL.grib2.bz2"
      done | xargs -P ${NPROC} -n 1 wget -q -c -P ${HHLDIR}
      if [ $(ls ${HHLDIR}/*_HHL.grib2.bz2 2>/dev/null | wc -l) -lt 121 ]
      then
         echo -e "${RED}==>${NC} HHL download incomplete in ${HHLDIR}. Run again to resume."
         exit 1
      fi
   fi

   # Topo do MONAN (m acima do nivel do mar), lido do namelist do init_atmosphere
   ZTOP=${ICON_ZTOP:-$(sed -n 's/^ *config_ztop *= *\([0-9.]*\).*/\1/p' ${SCRIPTS}/namelists/namelist.init_atmosphere.TEMPLATE)}
   if [ -z "${ZTOP}" ]
   then
      echo -e "${RED}==>${NC} config_ztop not found in ${SCRIPTS}/namelists/namelist.init_atmosphere.TEMPLATE (or set ICON_ZTOP)."
      exit 1
   fi

   # Niveis do modelo usados nesta rodada
   if [ ! -s ${OUT}/model_levels.txt ]
   then
      echo -e "${GREEN}==>${NC} Selecting ICON model levels (icon_levels.py, ztop = ${ZTOP} m)...\n"
      ${PYTHON} ${SCRIPTS}/icon_levels.py --hhl-dir ${HHLDIR} --ztop ${ZTOP} \
         --zfull ${ICON_ZFULL:-16000} --thin ${ICON_THIN:-2} > ${OUT}/model_levels.txt || exit 1
   fi
   MLEVELS=$(cat ${OUT}/model_levels.txt)
   echo -e "\nICON model levels ($(echo ${MLEVELS} | wc -w)): ${MLEVELS}\n"
   # config_nfglevels = 80 nos namelists: niveis escolhidos + superficie
   if [ $(echo ${MLEVELS} | wc -w) -gt 79 ]
   then
      echo -e "${RED}==>${NC} Too many levels for config_nfglevels = 80. Increase ICON_THIN or config_nfglevels."
      rm -f ${OUT}/model_levels.txt
      exit 1
   fi
elif [[ ${VCOORD} != "pressure" ]]
then
   echo -e "${RED}==>${NC} ICON_VCOORD must be model or pressure (got ${VCOORD})"
   exit 1
fi

urls=${OUT}/urls.txt; rm -f ${urls}
for item in ${TI}; do
   echo "${BASEURL}/${item%%:*}/icon_global_icosahedral_time-invariant_${YYYYMMDDHHi}_${item##*:}.grib2.bz2" >> ${urls}
done
if [[ ${VCOORD} == "model" ]]
then
   for ((hour=0; hour<=FCST; hour+=dt)); do
      fff=$(printf "%03d" ${hour})
      for item in ${ML}; do
         for k in ${MLEVELS}; do
            echo "${BASEURL}/${item%%:*}/icon_global_icosahedral_model-level_${YYYYMMDDHHi}_${fff}_${k}_${item##*:}.grib2.bz2" >> ${urls}
         done
      done
   done
else
   for item in ${PL}; do
      for f in $(listing ${item%%:*} pressure-level ${item##*:}); do
         fff=$(echo ${f} | awk -F_ '{print $6}')
         if [ $((10#${fff} % dt)) -eq 0 ] && [ $((10#${fff})) -le ${FCST} ]; then echo "${BASEURL}/${item%%:*}/${f}" >> ${urls}; fi
      done
   done
fi
for item in ${SOIL0}; do
   for f in $(listing ${item%%:*} soil-level ${item##*:} | grep "_${YYYYMMDDHHi}_000_"); do
      echo "${BASEURL}/${item%%:*}/${f}" >> ${urls}
   done
done
for ((hour=0; hour<=FCST; hour+=dt)); do
   fff=$(printf "%03d" ${hour})
   vars=${SL}; [ ${hour} -eq 0 ] && vars="${SL} ${SL0}"
   for item in ${vars}; do
      echo "${BASEURL}/${item%%:*}/icon_global_icosahedral_single-level_${YYYYMMDDHHi}_${fff}_${item##*:}.grib2.bz2" >> ${urls}
   done
done
#----------------------------------------------------------------------

echo -e "${GREEN}==>${NC} Downloading $(wc -l < ${urls}) ICON files to ${OUT} ...\n"
xargs -P ${NPROC} -n 1 wget -q -c -P ${OUT} < ${urls}

# Confere se veio tudo (horarios que ainda nao sairam no DWD tambem aparecem aqui)
nmiss=0
while read url; do
   if [ ! -s ${OUT}/$(basename ${url}) ]; then echo "Missing: ${url}"; nmiss=$((nmiss + 1)); fi
done < ${urls}
nlev=$(grep -c "_000_[0-9]*_T\.grib2" ${urls})
if [ ${nmiss} -ne 0 ] || [ ${nlev} -eq 0 ]
then
   echo -e "\n${RED}==>${NC} ${nmiss} files missing (${VCOORD} levels of T at 000: ${nlev}). Run again to resume.\n"
   exit 1
fi

rm -f ${urls}
echo "${FCST} ${dt} ${VCOORD}" > ${OUT}/download_ok
echo -e "\n${GREEN}==>${NC} ICON ${YYYYMMDDHHi} (+${FCST} h) downloaded: $(du -sh ${OUT} | cut -f1) in ${OUT}\n"
