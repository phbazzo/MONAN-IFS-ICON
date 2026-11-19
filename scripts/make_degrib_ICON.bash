#!/bin/bash
umask 022

if [ $# -ne 4 ]
then
   echo ""
   echo "Instructions: execute the command below"
   echo ""
   echo "${0} EXP RESOLUTION LABELI FCST"
   echo ""
   echo "EXP         :: Initial or lateral boundary condition dataset (GFS, ERA or ICON)"
   echo "RESOLUTION  :: Number of horizontal grid cells (global) or regional mesh identifier (e.g., 1024002 for the ~24 km mesh)"
   echo "LABELI      :: Forecast initialization date and time (YYYYMMDDHH), e.g., 2026080100"
   echo "FCST        :: Forecast length in hours (e.g., 24, 36, 48, etc.)"
   echo ""
   echo "Example of a 24-hour forecast:"
   echo "${0} ICON 655362 2026110500 24"
   echo ""
   exit
fi

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash

echo ""
echo "---- Make Degrib ${1} ----"
echo ""

# Standart directories variables:---------------------------------------
DIRHOMES=${DIR_SCRIPTS}/scripts_CD-CT;  mkdir -p ${DIRHOMES}
DIRHOMED=${DIR_DADOS}/scripts_CD-CT;    mkdir -p ${DIRHOMED}
SCRIPTS=${DIRHOMES}/scripts;            mkdir -p ${SCRIPTS}
DATAIN=${DIRHOMED}/datain;              mkdir -p ${DATAIN}
DATAOUT=${DIRHOMED}/dataout;            mkdir -p ${DATAOUT}
SOURCES=${DIRHOMES}/sources;            mkdir -p ${SOURCES}
EXECS=${DIRHOMED}/execs;                mkdir -p ${EXECS}
#----------------------------------------------------------------------


# Input variables:--------------------------------------
EXP=${1};         #EXP=ICON
RES=${2};         #RES=1024002
YYYYMMDDHHi=${3}; #YYYYMMDDHHi=2026110500
FCST=${4};        #FCST=24
# Rodada: saidas em dataout/LABELI/EXP[_RUN_TAG] (run_name no setenv.bash), para o mesmo LABELI
# poder ser rodado com CI/CC diferentes sem sobrescrever (e em paralelo: run.LABELI.RUNNAME)
RUNNAME=$(run_name ${EXP}) || exit 1
OUTRUN=${DATAOUT}/${YYYYMMDDHHi}/${RUNNAME}
#-------------------------------------------------------

# Local variables--------------------------------------
start_date=${YYYYMMDDHHi:0:4}-${YYYYMMDDHHi:4:2}-${YYYYMMDDHHi:6:2}_${YYYYMMDDHHi:8:2}:00:00
export DIRRUN=${DIRHOMED}/run.${YYYYMMDDHHi}.${RUNNAME}; rm -fr ${DIRRUN}; mkdir -p ${DIRRUN}
# ICON_RUN: rodada do ICON usada (padrao = LABELI). Se for anterior ao LABELI, a CI e a PREVISAO do
# ICON valida em LABELI (prazo START = LABELI - ICON_RUN), ex.: ICON_RUN=2026111900 com LABELI=2026112100
ICONRUN=${ICON_RUN:-${YYYYMMDDHHi}}
START=$(( ( $(date -u -d "${YYYYMMDDHHi:0:8} ${YYYYMMDDHHi:8:2}:00" +%s) - $(date -u -d "${ICONRUN:0:8} ${ICONRUN:8:2}:00" +%s) ) / 3600 ))
if [ ${START} -lt 0 ]
then
   echo -e "${RED}==>${NC} ICON_RUN=${ICONRUN} is after LABELI=${YYYYMMDDHHi}."
   exit -1
fi
SOILLEAD=${ICON_SOIL_LEAD:-${START}}
BNDDIR=${DATAIN}/ICON/${ICONRUN}
ICONCDO=${DATAIN}/fixed/icon_cdo
HHLDIR=${DATAIN}/fixed/icon_hhl
VCOORD=${ICON_VCOORD:-model}   # model (niveis do modelo do ICON) ou pressure (18 niveis de pressao)

# Python com numpy e eccodes, e o cdo (ajuste se nao estiverem no PATH), ex.:
#   export ICON_PYTHON=${HOME}/.conda/envs/met_plot/bin/python
PYTHON=$(find_python) || exit 1   # numpy + eccodes (ICON_PYTHON ou ambiente conda; ver setenv.bash)
# cdo: ICON_CDO; senao o do mesmo ambiente conda do Python; senao o do PATH. O do modulo cdo/2.4.2 da
# JACI (compilado com o OpenMP da Cray) falha com "CCE OpenMP fatal error: omp_set_num_threads attempted
# from non-OpenMP thread"; com caminho completo, o icon2wps.py roda o cdo sem o LD_LIBRARY_PATH da Cray.
if [ -n "${ICON_CDO}" ]
then
   CDO=${ICON_CDO}
elif [ -x "$(dirname ${PYTHON})/cdo" ]
then
   CDO=$(dirname ${PYTHON})/cdo
else
   CDO=cdo
fi
echo -e "${GREEN}==>${NC} cdo: ${CDO}\n"
NPROC=${ICON_NPROC:-8}
#-------------------------------------------------------
mkdir -p ${OUTRUN}/Pre/logs

# O ICON e baixado antes, com ICON_START=${START} ./get_icon_dwd.bash ${ICONRUN} $((START + FCST))
files_needed=("${SCRIPTS}/icon2wps.py" "${ICONCDO}/target_grid.txt" "${ICONCDO}/weights.nc" "${BNDDIR}/icon_global_icosahedral_time-invariant_${ICONRUN}_HSURF.grib2.bz2")
if [[ ${VCOORD} == "model" ]]; then files_needed+=("${BNDDIR}/model_levels.txt"); fi
for file in "${files_needed[@]}"
do
  if [ ! -s "${file}" ]
  then
    echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
    echo -e  "${RED}==>${NC} [${0}] At least the file ${file} was not found. \n"
    echo -e  "${RED}==>${NC} Run first: ICON_START=${START} ./get_icon_dwd.bash ${ICONRUN} $((START + FCST)) \n"
    exit -1
  fi
done

if [[ $MODERUN == "R" ]]; then
   echo -e "Converting ICON data for Regional (limited-area) mode – lateral boundary conditions.\n"
   fcst=${FCST}
   box=${ICON_BOX:-"-95,-25,-60,15"}   # lon1,lon2,lat1,lat2 - precisa cobrir o dominio regional
elif [[ ${MODERUN} == "G" ]]; then
   echo -e "Converting ICON data for Global mode – only initial conditions.\n"
   fcst=0
   box=global
else
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} Make degrib phase fails during degrib! Please select MODERUN=R or G so that degrib can be done appropriately.\n"
   echo -e  "${RED}==>${NC} Exiting script. \n"
   exit -1
fi

if [ ${START} -gt 0 ]
then
   echo -e "${GREEN}==>${NC} Initial condition = ICON ${ICONRUN} forecast at +${START} h (valid ${YYYYMMDDHHi}); soil/snow/ice at +${SOILLEAD} h\n"
fi

# CDO remap + conversao para intermediarios do WPS (faz o papel do ungrib)
cd ${DIRRUN}
time ${PYTHON} ${SCRIPTS}/icon2wps.py --indir ${BNDDIR} --run ${ICONRUN} \
   --start ${START} --soil-lead ${SOILLEAD} \
   --fcst ${fcst} --step $((LBCINT / 3600)) \
   --grid ${ICONCDO}/target_grid.txt --weights ${ICONCDO}/weights.nc --box="${box}" \
   --vcoord ${VCOORD} --hhl-dir ${HHLDIR} \
   --prefix ${EXP} --cdo ${CDO} --nproc ${NPROC} --outdir ${DIRRUN} \
   2>&1 | tee ${OUTRUN}/Pre/logs/icon2wps.${start_date}.log

if [ ${PIPESTATUS[0]} -ne 0 ]
then
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} icon2wps.py failed! Check ${OUTRUN}/Pre/logs/icon2wps.${start_date}.log \n"
   exit -1
fi

mv ${DIRRUN}/${EXP}\:* ${OUTRUN}/Pre

files_ungrib=("${EXP}:${YYYYMMDDHHi:0:4}-${YYYYMMDDHHi:4:2}-${YYYYMMDDHHi:6:2}_${YYYYMMDDHHi:8:2}")
for file in "${files_ungrib[@]}"
do
  if [ ! -s ${OUTRUN}/Pre/${file} ]
  then
    echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
    echo -e  "${RED}==>${NC} Degrib fails! At least the file ${file} was not generated at ${OUTRUN}/Pre. \n"
    echo -e  "${RED}==>${NC} Check logs at ${OUTRUN}/Pre/logs/icon2wps.* .\n"
    echo -e  "${RED}==>${NC} Exiting script. \n"
    exit -1
  fi
done

chmod -R 755 ${OUTRUN}/Pre/*
cd ${SCRIPTS}
rm -fr ${DIRRUN}
