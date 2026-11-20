#!/bin/bash
umask 022
#-----------------------------------------------------------------------------#
# !SCRIPT: prev_mapas_nativo   (PROVISORIO: alternativa enquanto o pos lat-lon falha)
#
# !DESCRIPTION:
#     Os mesmos mapas do 5.prev_mapas.bash, lidos direto das saidas nativas do modelo
#     (dataout/LABELI/RUNNAME/Model/MONAN_DIAG_*_MOD_*.nc), sem precisar do 4.run_post.bash.
#     A grade lat-lon vem do latCell/lonCell do Pre/x1.RES.init.nc (ou datain/fixed/x1.RES.static.nc).
#     Saida: dataout/LABELI/RUNNAME/Figs_nativo/{chuva6h,ambiente,refletividade}/
#
#     Variaveis: as do 5.prev_mapas.bash (PREV_ACUM, PREV_STEP, PREV_BOX, PREV_LABEL, PREV_NPROC,
#     PREV_ONLY, PLOT_PYTHON) e PREV_DX (graus, vazio = ~ espacamento da malha).
#-----------------------------------------------------------------------------#

if [ $# -ne 4 ]
then
   echo ""
   echo "Instructions: execute the command below"
   echo ""
   echo "${0} EXP RESOLUTION LABELI FCST"
   echo ""
   echo "EXP         :: Initial or lateral boundary condition dataset (GFS, ERA, ICON, IFS)"
   echo "RESOLUTION  :: Mesh identifier, as in 4.run_post.bash (e.g., 1024002)"
   echo "LABELI      :: Forecast initialization date and time (YYYYMMDDHH), e.g., 2026111900"
   echo "FCST        :: Forecast length in hours (e.g., 24, 36, 48, etc.)"
   echo ""
   echo "Example (Sul, title, after 3.run_model.bash):"
   echo "PREV_BOX=-58,-47,-34,-22 PREV_LABEL='MONAN ICON L75' ${0} ICON 223909_3SUL 2026111900 72"
   echo ""
   exit
fi

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash

# Standart directories variables:---------------------------------------
DIRHOMES=$(dirname "$(pwd)")
DIRHOMED=${DIR_DADOS}/scripts_CD-CT
SCRIPTS=${DIRHOMES}/scripts
DATAOUT=${DIRHOMED}/dataout
#----------------------------------------------------------------------

# Input variables:--------------------------------------
EXP=${1};         #EXP=ICON
RES=${2};         #RES=1024002
YYYYMMDDHHi=${3}; #YYYYMMDDHHi=2026111900
FCST=${4};        #FCST=48
RUNNAME=$(run_name ${EXP}) || exit 1
OUTRUN=${DATAOUT}/${YYYYMMDDHHi}/${RUNNAME}
POSTDIR=${OUTRUN}/Model
FIGDIR=${OUTRUN}/Figs_nativo
#-------------------------------------------------------

nfiles=$(ls ${POSTDIR}/MONAN_DIAG_*_MOD_*_${YYYYMMDDHHi}_*.x${RES}L*.nc 2>/dev/null | wc -l)
if [ ${nfiles} -eq 0 ]
then
   echo -e "${RED}==>${NC} No MONAN_DIAG_*_MOD_*_${YYYYMMDDHHi}_*.x${RES}L*.nc in ${POSTDIR}."
   exit 1
fi
MESH=${OUTRUN}/Pre/x1.${RES}.init.nc
[ -s ${MESH} ] || MESH=${DIRHOMED}/datain/fixed/x1.${RES}.static.nc
for file in ${SCRIPTS}/prev_mapas.py ${SCRIPTS}/prev_mapas_nativo.py ${MESH}
do
   if [ ! -s ${file} ]
   then
      echo -e "${RED}==>${NC} ${file} not found."
      exit 1
   fi
done

PYTHON=$(find_python "numpy, netCDF4, matplotlib, cartopy" PLOT_PYTHON) || exit 1
mkdir -p ${FIGDIR}

echo -e "${GREEN}==>${NC} Forecast maps (native): ${nfiles} model files in ${POSTDIR}"
echo -e "${GREEN}==>${NC} Mesh: ${MESH}"
echo -e "${GREEN}==>${NC} Python: ${PYTHON}\n"

${PYTHON} ${SCRIPTS}/prev_mapas_nativo.py --mesh ${MESH} ${PREV_DX:+--dx ${PREV_DX}} \
   --post-dir ${POSTDIR} --out ${FIGDIR} \
   --labeli ${YYYYMMDDHHi} --fcst ${FCST} \
   --acum ${PREV_ACUM:-6} --step ${PREV_STEP:-3} --nproc ${PREV_NPROC:-4} \
   ${PREV_BOX:+--box=${PREV_BOX}} ${PREV_ONLY:+--only ${PREV_ONLY}} \
   --label "${PREV_LABEL:-MONAN ${RUNNAME} x${RES}}" || exit 1

echo -e "\n${GREEN}==>${NC} Figures in ${FIGDIR}\n"
