#!/bin/bash
umask 022

if [ $# -ne 4 ]
then
   echo ""
   echo "Instructions: execute the command below"
   echo ""
   echo "${0} EXP RESOLUTION LABELI FCST"
   echo ""
   echo "EXP         :: Initial or lateral boundary condition dataset (GFS, ERA, ICON or IFS)"
   echo "RESOLUTION  :: Number of horizontal grid cells (global) or regional mesh identifier (e.g., 1024002 for the ~24 km mesh)"
   echo "LABELI      :: Forecast initialization date and time (YYYYMMDDHH), e.g., 2026080100"
   echo "FCST        :: Forecast length in hours (e.g., 24, 36, 48, etc.)"
   echo ""
   echo "Example of a 24-hour forecast:"
   echo "${0} IFS 655362 2026110500 24"
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
EXP=${1};         #EXP=IFS
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
BNDDIR=${DATAIN}/IFS/${YYYYMMDDHHi}

# Python com numpy e eccodes (o mesmo do ICON), ex.:
#   export ICON_PYTHON=${HOME}/.conda/envs/met_plot/bin/python
PYTHON=$(find_python) || exit 1   # numpy + eccodes (ICON_PYTHON ou ambiente conda; ver setenv.bash)
#-------------------------------------------------------
mkdir -p ${OUTRUN}/Pre/logs

# O IFS e baixado antes, com ./get_ifs_ecmwf.bash ${YYYYMMDDHHi} ${FCST}
files_needed=("${SCRIPTS}/ifs2wps.py" "${SCRIPTS}/icon2wps.py" "${BNDDIR}/ifs_sfc0.grib2" "${BNDDIR}/ifs_sol.grib2" "${BNDDIR}/ifs_pl.000.grib2" "${BNDDIR}/ifs_sfc.000.grib2")
for file in "${files_needed[@]}"
do
  if [ ! -s "${file}" ]
  then
    echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
    echo -e  "${RED}==>${NC} [${0}] At least the file ${file} was not found. \n"
    echo -e  "${RED}==>${NC} Run first: ./get_ifs_ecmwf.bash ${YYYYMMDDHHi} ${FCST} \n"
    exit -1
  fi
done

if [[ $MODERUN == "R" ]]; then
   echo -e "Converting IFS data for Regional (limited-area) mode – lateral boundary conditions.\n"
   fcst=${FCST}
   box=${IFS_BOX:-${ICON_BOX:-"-95,-25,-60,15"}}   # lon1,lon2,lat1,lat2 - precisa cobrir o dominio regional
elif [[ ${MODERUN} == "G" ]]; then
   echo -e "Converting IFS data for Global mode – only initial conditions.\n"
   fcst=0
   box=global
else
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} Make degrib phase fails during degrib! Please select MODERUN=R or G so that degrib can be done appropriately.\n"
   echo -e  "${RED}==>${NC} Exiting script. \n"
   exit -1
fi

# Recorte + conversao para intermediarios do WPS (faz o papel do ungrib)
cd ${DIRRUN}
time ${PYTHON} ${SCRIPTS}/ifs2wps.py --indir ${BNDDIR} --run ${YYYYMMDDHHi} \
   --fcst ${fcst} --step $((LBCINT / 3600)) --box="${box}" \
   --prefix ${EXP} --outdir ${DIRRUN} \
   2>&1 | tee ${OUTRUN}/Pre/logs/ifs2wps.${start_date}.log

if [ ${PIPESTATUS[0]} -ne 0 ]
then
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} ifs2wps.py failed! Check ${OUTRUN}/Pre/logs/ifs2wps.${start_date}.log \n"
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
    echo -e  "${RED}==>${NC} Check logs at ${OUTRUN}/Pre/logs/ifs2wps.* .\n"
    echo -e  "${RED}==>${NC} Exiting script. \n"
    exit -1
  fi
done

chmod -R 755 ${OUTRUN}/Pre/*
cd ${SCRIPTS}
rm -fr ${DIRRUN}
