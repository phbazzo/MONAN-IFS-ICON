#!/bin/bash
umask 022
#-----------------------------------------------------------------------------#
# !SCRIPT: prev_mapas
#
# !DESCRIPTION:
#     Mapas de previsao a partir do pos do MONAN (4.run_post.bash), com prev_mapas.py:
#
#        o chuva acumulada em PREV_ACUM h (padrao 6), rotulada pelo FIM da janela (H-6, H]
#        o ambiente pre-convectivo a cada PREV_STEP h (padrao 3): MUCAPE/MUCIN, MLCAPE/MLCIN,
#          cisalhamento 0-6 e 0-1 km, SRH 0-3 km (contornos 0-1 km), agua precipitavel e vento 10 m
#
#     Entrada: dataout/LABELI/RUNNAME/Post/MONAN_DIAG_*_POS_*.nc
#     Saida:   dataout/LABELI/RUNNAME/Figs/{chuva6h,ambiente}_LABELI_fHHH.png
#
#     Roda no no de login, sem fila. Na 1a vez o cartopy baixa costa/fronteiras/estados do
#     Natural Earth (precisa de internet, como no login da JACI).
#     Precisa de Python com numpy, netCDF4, matplotlib e cartopy: PLOT_PYTHON, ou vazio = procura
#     nos ambientes conda do usuario (find_python, setenv.bash).
#
#     Variaveis opcionais:
#        PREV_ACUM  (6)   janela da chuva acumulada, h
#        PREV_STEP  (3)   intervalo dos mapas de ambiente, h
#        PREV_BOX   ("")  recorte "W,E,S,N" em graus, ex.: "-58,-47,-34,-22"; vazio = grade toda do pos
#        PREV_LABEL ("")  titulo da rodada; vazio = "MONAN RUNNAME xRES"
#        PREV_NPROC (4)   figuras em paralelo
#        PREV_ONLY  ("")  chuva | ambiente: so um tipo de mapa
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
   echo "Example (Sul, title, after 4.run_post.bash):"
   echo "PREV_BOX=-58,-47,-34,-22 PREV_LABEL='MONAN ICON L75' ${0} ICON 1024002 2026111900 48"
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
POSTDIR=${OUTRUN}/Post
FIGDIR=${OUTRUN}/Figs
#-------------------------------------------------------

nfiles=$(ls ${POSTDIR}/MONAN_DIAG_*_POS_${EXP}_${YYYYMMDDHHi}_*.x${RES}L*.nc 2>/dev/null | wc -l)
if [ ${nfiles} -eq 0 ]
then
   echo -e "${RED}==>${NC} No MONAN_DIAG_*_POS_${EXP}_${YYYYMMDDHHi}_*.x${RES}L*.nc in ${POSTDIR}. Run 4.run_post.bash first."
   exit 1
fi
if [ ! -s ${SCRIPTS}/prev_mapas.py ]
then
   echo -e "${RED}==>${NC} ${SCRIPTS}/prev_mapas.py not found."
   exit 1
fi

PYTHON=$(find_python "numpy, netCDF4, matplotlib, cartopy" PLOT_PYTHON) || exit 1
mkdir -p ${FIGDIR}

echo -e "${GREEN}==>${NC} Forecast maps: ${nfiles} post files in ${POSTDIR}"
echo -e "${GREEN}==>${NC} Python: ${PYTHON}\n"

${PYTHON} ${SCRIPTS}/prev_mapas.py \
   --post-dir ${POSTDIR} --out ${FIGDIR} \
   --labeli ${YYYYMMDDHHi} --fcst ${FCST} \
   --acum ${PREV_ACUM:-6} --step ${PREV_STEP:-3} --nproc ${PREV_NPROC:-4} \
   ${PREV_BOX:+--box=${PREV_BOX}} ${PREV_ONLY:+--only ${PREV_ONLY}} \
   --label "${PREV_LABEL:-MONAN ${RUNNAME} x${RES}}" || exit 1

echo -e "\n${GREEN}==>${NC} Figures in ${FIGDIR}\n"
