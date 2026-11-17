#!/bin/bash 
umask 022
set -e
trap 'echo -e "\n${RED}==>${NC} $(basename "$0") failed.\n"' ERR
#-----------------------------------------------------------------------------#
# !SCRIPT: pre_processing
#
# !DESCRIPTION:
#     Script to prepare boundary and initials conditions for MONAN model.
#     
#     Performs the following tasks:
# 
#        o Downloads ICON (get_icon_dwd.bash) or IFS (get_ifs_ecmwf.bash) data
#        o Creates topography, land use and static variables
#        o Ungrib GFS or ERA5 data, or converts ICON/IFS (icon2wps.py/ifs2wps.py)
#        o Interpolates to model the grid
#        o Creates initial and boundary conditions
#        o Creates scripts to run the model and post-processing (CR: to be modified to phase 3 and 4)
#        o Integrates the MONAN model ((CR: to be modified to phase 3)
#        o Post-processing (netcdf for grib2, latlon regrid, crop) (CR: to be modified to phase 4)
#
#-----------------------------------------------------------------------------#

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
   echo "${0} GFS 655362 2026080100 24"
   echo "${0} ICON 223909_3SUL $(date -u +%Y%m%d)00 48"
   echo ""
   echo "ICON e IFS sao baixados automaticamente antes da conversao (no no de login, precisa de internet)."
   echo "ATENCAO: normalmente so as rodadas do DIA estao disponiveis:"
   echo "   ICON (DWD opendata)    : so as ultimas ~24 h (rodadas 00, 06, 12 e 18 UTC)."
   echo "   IFS  (ECMWF open data) : ~2-3 ultimos dias no portal do ECMWF; datas mais antigas"
   echo "                            com 'export IFS_SOURCE=aws' (arquivo desde 2023)."
   echo "   Arquivos ja baixados em datain/ICON|IFS/LABELI sao reaproveitados."
   echo ""
   exit
fi

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash


echo ""
echo "---- Pre Processing ----"
echo ""


# Standard directories variables:---------------------------------------
DIRHOMES=${DIR_SCRIPTS}/scripts_CD-CT; mkdir -p ${DIRHOMES}    
DIRHOMED=${DIR_DADOS}/scripts_CD-CT;   mkdir -p ${DIRHOMED}  
SCRIPTS=${DIRHOMES}/scripts;           mkdir -p ${SCRIPTS}
DATAIN=${DIRHOMED}/datain;             mkdir -p ${DATAIN}
DATAOUT=${DIRHOMED}/dataout;           mkdir -p ${DATAOUT}
SOURCES=${DIRHOMES}/sources;           mkdir -p ${SOURCES}
EXECS=${DIRHOMED}/execs;               mkdir -p ${EXECS}
#----------------------------------------------------------------------


# Input variables:--------------------------------------
EXP=${1};         #EXP=GFS
RES=${2};         #RES=1024002
YYYYMMDDHHi=${3}; #YYYYMMDDHHi=2024012000
FCST=${4};        #FCST=24
# Rodada: saidas em dataout/LABELI/EXP[_RUN_TAG] (run_name no setenv.bash), para o mesmo LABELI
# poder ser rodado com CI/CC diferentes sem sobrescrever (e em paralelo: run.LABELI.RUNNAME)
RUNNAME=$(run_name ${EXP}) || exit 1
OUTRUN=${DATAOUT}/${YYYYMMDDHHi}/${RUNNAME}
#-------------------------------------------------------


# Local variables--------------------------------------
# Calculating CIs and final forecast dates in model namelist format:
yyyymmddi=${YYYYMMDDHHi:0:8}
hhi=${YYYYMMDDHHi:8:2}
yyyymmddhhf=$(date +"%Y%m%d%H" -d "${yyyymmddi} ${hhi}:00 ${FCST} hours" )
final_date=${yyyymmddhhf:0:4}-${yyyymmddhhf:4:2}-${yyyymmddhhf:6:2}_${yyyymmddhhf:8:2}.00.00
export DIRRUN=${DIRHOMED}/run.${YYYYMMDDHHi}.${RUNNAME}; rm -fr ${DIRRUN}; mkdir -p ${DIRRUN}
#-------------------------------------------------------

echo -e  "${GREEN}==>${NC} Run ${RUNNAME} ${YYYYMMDDHHi}: outputs in ${OUTRUN}/{Pre,Model,Post}\n"
echo -e  "${GREEN}==>${NC} Scripts_CD-CT last commit: \n"
git log | head -1


# Download do ICON/IFS (antes de tudo: se a rodada nao estiver disponivel, para aqui)
if [[ ${EXP} == "ICON" || ${EXP} == "IFS" ]]
then
   if [[ ! ${hhi} =~ ^(00|06|12|18)$ ]]
   then
      echo -e "\n${RED}==>${NC} ${EXP}: LABELI must be a 00, 06, 12 or 18 UTC run (got ${YYYYMMDDHHi}).\n"
      exit -1
   fi
   age=$(( ( $(date -u +%s) - $(date -u -d "${yyyymmddi} ${hhi}:00" +%s) ) / 3600 ))
   if [[ ${EXP} == "ICON" && ${age} -gt 24 ]] || [[ ${EXP} == "IFS" && ${age} -gt 72 && ${IFS_SOURCE:-ecmwf} == "ecmwf" ]]
   then
      echo -e "${RED}==>${NC} Warning: ${EXP} ${YYYYMMDDHHi} is ${age} h old and may no longer be online"
      echo -e "${RED}==>${NC} (ICON: last ~24 h; IFS: last ~2-3 days, or IFS_SOURCE=aws). Trying anyway...\n"
   fi
   # Python com numpy + eccodes (procura uma vez e exporta para os scripts filhos)
   export ICON_PYTHON=$(find_python)
   if [ -z "${ICON_PYTHON}" ]; then exit -1; fi
   echo -e "${GREEN}==>${NC} Python for GRIB conversion: ${ICON_PYTHON}\n"
   cd ${SCRIPTS}
   if [[ ${EXP} == "ICON" ]]
   then
      echo -e "${GREEN}==>${NC} Downloading ICON ${YYYYMMDDHHi} (+${FCST} h)...\n"
      time ./get_icon_dwd.bash ${YYYYMMDDHHi} ${FCST}
   else
      echo -e "${GREEN}==>${NC} Downloading IFS ${YYYYMMDDHHi} (+${FCST} h)...\n"
      time ./get_ifs_ecmwf.bash ${YYYYMMDDHHi} ${FCST}
   fi
fi


if [ ! -d ${DATAIN}/fixed ]
then
	echo -e  "${GREEN}==>${NC} copying and linking fixed input data ${SYSTEM_KEYC}... \n"
	mkdir -p ${DATAIN}
	rsync -rv --chmod=ugo=rw ${DIRDADOS}/MONAN_datain/datain/fixed ${DATAIN}
	rsync -rv --chmod=ugo=rwx ${DIRDADOS}/MONAN_datain/execs ${DIRHOMED}
	ln -sf ${DIRDADOS}/MONAN_datain/datain/WPS_GEOG ${DATAIN}
fi
#----------------------------------------------------------------------------------

# Building MP_THOMPSON DBL tables
echo ""
echo -e  "${GREEN}==>${NC} Building MP_THOMPSON DBL tables ...\n"

files_needed=("${DATAIN}/fixed/MP_THOMPSON_QRacrQG_DATA.DBL" "${DATAIN}/fixed/MP_THOMPSON_QRacrQS_DATA.DBL" "${DATAIN}/fixed/MP_THOMPSON_freezeH2O_DATA.DBL" "${DATAIN}/fixed/MP_THOMPSON_QIautQS_DATA.DBL")

if [ ! -s ${DATAIN}/fixed/MP_THOMPSON_QRacrQG_DATA.DBL ]  || [ ! -s ${DATAIN}/fixed/MP_THOMPSON_QRacrQS_DATA.DBL ] || [ ! -s ${DATAIN}/fixed/MP_THOMPSON_freezeH2O_DATA.DBL ] || [ ! -s ${DATAIN}/fixed/MP_THOMPSON_QIautQS_DATA.DBL ]; then
   echo -e  "${GREEN}==>${NC} This calculation can take around 2 minutes on a supercomputer...\n"

   rm -f ${EXECS}/MP_THOMPSON_*_DATA.DBL
   rm -f ${DATAIN}/fixed/MP_THOMPSON_*_DATA.DBL

   cd ${EXECS}
   ${EXECS}/build_tables

   mv ${EXECS}/MP_THOMPSON_QRacrQG_DATA.DBL    ${DATAIN}/fixed
   mv ${EXECS}/MP_THOMPSON_QRacrQS_DATA.DBL    ${DATAIN}/fixed
   mv ${EXECS}/MP_THOMPSON_freezeH2O_DATA.DBL  ${DATAIN}/fixed
   mv ${EXECS}/MP_THOMPSON_QIautQS_DATA.DBL    ${DATAIN}/fixed

   chmod 755 ${DATAIN}/fixed/MP_THOMPSON_*_DATA.DBL
   chgrp $USER ${DATAIN}/fixed/MP_THOMPSON_*_DATA.DBL

   # verify here if the tables were created 
   for file in "${files_needed[@]}"
   do
     if [ -s "${file}" ] ; then
       echo ""
       echo -e "${GREEN}==>${NC} File ${file} generated sucessfully in ${EXECS} and moved to ${DATAIN}/fixed!"
       echo
     else
       echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"   
       echo -e  "${RED}==>${NC} [${0}] An error occurred during MP_THOMPSON build_tables. At least the file ${file} was not generated. \n"
       exit -1
     fi
   done
else
   echo -e "${GREEN}==>${NC} MP_THOMPSON DBL tables already exist in ${DATAIN}/fixed!"
fi


# Copying NoahmpTable.TBL from source to datain folder
echo ""
echo -e "${GREEN}==>${NC} Copying NoahmpTable.TBL from source code to datain fixed folder ...\n"

if [ ! -s ${DATAIN}/fixed/NoahmpTable.TBL ]
then
   if [ -s ${MONANDIR}/src/core_atmosphere/physics/physics_noahmp/parameters/NoahmpTable.TBL ]; then
      cp -f ${MONANDIR}/src/core_atmosphere/physics/physics_noahmp/parameters/NoahmpTable.TBL ${DATAIN}/fixed
      chmod 755 ${DATAIN}/fixed/NoahmpTable.TBL
   else
      echo -e "${RED}==>${NC} File NoahmpTable.TBL not found in ${MONANDIR}. Please run script 1.install_monan.bash first. \n"
      exit -1
   fi
else
   echo -e "${GREEN}==>${NC} File NoahmpTable.TBL already exist in ${DATAIN}/fixed.\n"
fi

#TODO: EGK - Verify if necessary data for NOAH-MP soil colour pre-processing is present in datain folder
echo -e "${GREEN}==>${NC} Verifying if clm_soilcolour_21class_30s exist in datain WPS_GEOG folder for running NOAH-MP model with MONAN soil colour table activated ...\n"

if [ ! -d ${DATAIN}/WPS_GEOG/clm_soilcolour_21class_30s/ ]
then
   mkdir -p ${DATAIN}/WPS_GEOG
   cd ${DATAIN}/WPS_GEOG
   echo -e "${GREEN}==>${NC} downloading clm_soilcolour_21class_30s/ folder...\n"
# needs to download data from MONAN dataserver or some mirror... 
#   rm -f ${DATAIN}/WPS_GEOG/wget-log*
#   wget https://...
#   ln -sf ${DIRDADOS}/MONAN_datain/datain/WPS_GEOG/clm_soilcolour_21class_30s ${DATAIN}/WPS_GEOG
else
   echo -e "${GREEN}==>${NC} Folder clm_soilcolour_21class_30s already exist in ${DATAIN}/WPS_GEOG.\n"
fi


# moving back to scripts folder
cd ${SCRIPTS}


# Creating the x1.${RES}.static.nc file once, if does not exist yet:---------------
if [[ ${EXP} == "GFS" || ${EXP} == "ERA" || ${EXP} == "ICON" || ${EXP} == "IFS" ]]; then
   if [ ! -s ${DATAIN}/fixed/x1.${RES}.static.nc ]
   then
      echo -e "${GREEN}==>${NC} Creating static.bash for submiting init_atmosphere to create x1.${RES}.static.nc...\n"
      time ./make_static.bash ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
   else
      echo -e "${GREEN}==>${NC} File x1.${RES}.static.nc already exist in ${DATAIN}/fixed.\n"
   fi
else
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} Static phase fails! Please select EXP=GFS, EXP=ERA, EXP=ICON or EXP=IFS.\n"
   echo -e  "${RED}==>${NC} Exiting script. \n"
   exit -1
fi

#----------------------------------------------------------------------------------

# Degrib phase:---------------------------------------------------------------------
if [[ ${EXP} == "GFS" ]]
then
   echo -e  "${GREEN}==>${NC} Submitting Degrib for GFS data...\n"
   time ./make_degrib_GFS.bash ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
elif [[ ${EXP} == "ERA" ]]
then
   echo -e  "${GREEN}==>${NC} Submitting Degrib for ERA data...\n"
   time ./make_degrib_ERA5.bash ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
elif [[ ${EXP} == "ICON" ]]
then
   echo -e  "${GREEN}==>${NC} Converting ICON data (CDO remap + icon2wps.py)...\n"
   time ./make_degrib_ICON.bash ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
elif [[ ${EXP} == "IFS" ]]
then
   echo -e  "${GREEN}==>${NC} Converting IFS data (ifs2wps.py)...\n"
   time ./make_degrib_IFS.bash ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
else
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} Degrib phase fails! Please select EXP=GFS, EXP=ERA, EXP=ICON or EXP=IFS.\n"
   echo -e  "${RED}==>${NC} Exiting script. \n"
   exit -1
fi
#----------------------------------------------------------------------------------

# Init Atmosphere phase:------------------------------------------------------------
if [[ ${EXP} == "GFS" || ${EXP} == "ERA" || ${EXP} == "ICON" || ${EXP} == "IFS" ]]; then
   echo -e  "\n${GREEN}==>${NC} Submitting Init Atmosphere for real case...\n"
   time ./make_initatmos.bash ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
else
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} Init Atmosphere phase fails! Please select EXP=GFS, EXP=ERA, EXP=ICON or EXP=IFS.\n"
   echo -e  "${RED}==>${NC} Exiting script. \n"
   exit -1
fi
#----------------------------------------------------------------------------------

# LBCs phase:------------------------------------------------------------
if [[ $MODERUN == "R" ]]; then
   time ./make_lbcs.bash ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
elif [[ $MODERUN == "G" ]]; then
   : # it doesn't need the LBC (lateral boundary conditions)
else
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} LBCs phase fails! Please select MODERUN=R or G.\n"
   echo -e  "${RED}==>${NC} Exiting script. \n"
   exit -1
fi
#----------------------------------------------------------------------------------
echo -e "\n$(basename "$0") completed successfully.\n"
