#!/bin/bash
umask 022

# Choose the simulation mode:
export MODERUN=R     # R=Regional simulation and G=Global simulation.
export LBCINT=10800  # Interval (seconds) for updating lateral boundary conditions (when regional mode).

# Grade vertical (namelists do init_atmosphere, nomes dos arquivos do modelo e do pos):
export NVERTLEV=75                        # config_nvertlevels
export ZETA_LEVELS=zeta_levels.L75.txt    # em namelists/ (gerado por zeta_levels.py), com NVERTLEV+1 alturas;
                                          # vazio = grade TC padrao do MPAS (config_tc_vertical_grid)

# Rodadas: as saidas ficam em dataout/LABELI/RUNNAME/{Pre,Model,Post}, com RUNNAME = EXP ou EXP_RUN_TAG.
# O mesmo LABELI com CI/CC diferentes (ICON, IFS, GFS...) ja fica separado pelo EXP. Para variar outra coisa
# com o mesmo EXP (niveis, fisica...), de um rotulo antes de rodar, ex.:
#    RUN_TAG=L55 ./0.run_all.bash ICON 223909_3SUL 2026111300 48   ->  dataout/2026111300/ICON_L55/
export RUN_TAG=${RUN_TAG:-}

# Python com numpy + eccodes para ICON/IFS (icon_levels.py, icon2wps.py, ifs2wps.py). Vazio = procura
# sozinho nos ambientes conda do usuario (find_python, abaixo). Para fixar um, ex.:
#    export ICON_PYTHON=${HOME}/.conda/envs/<ambiente>/bin/python
export ICON_PYTHON=${ICON_PYTHON:-}
# cdo do ICON: vazio = o cdo do mesmo ambiente conda do ICON_PYTHON (o modulo cdo/2.4.2 da Cray falha)
export ICON_CDO=${ICON_CDO:-}

# Choose your compiler here (only on Jaci; on Egeon the compiler is fixed to ‘gnu’):
export COMPILER=intel
#export COMPILER=gnu
#export COMPILER=cray
#export COMPILER=nvidia

# Squeduler detect:
if command -v sbatch &> /dev/null
then
   export SCHEDULER_SYSTEM="SLURM"
   echo "SLURM detected." 
elif command -v qsub &> /dev/null
then
   export SCHEDULER_SYSTEM="PBS"
   echo "PBS detected."
else
   export SCHEDULER_SYSTEM="GENERIC"
   echo "No SCHEDULER detected."
fi

# Detect hostname
THOSTNAME=$(hostname -s)

# Identifying several names of the egeon:
case ${THOSTNAME} in
   egeon-login|headnode|n[0-9]|n[1-2][0-9]|n3[0-3])
      export HOSTNAME="egeon"
      export MAKE_TARG=gfortran
      export MAKE_TARG2=gfortran
      COMPILER=gnu
      ;;
   ian[0-9]*|cn-0[0-9][0-9][0-9])
      export HOSTNAME="ian"
      if [ "$COMPILER" == "intel" ]; then
         export MAKE_TARG=intel-xd2000
         export MAKE_TARG2=intel2-xd2000
      elif [ "$COMPILER" == "gnu" ]; then
         export MAKE_TARG=gfortran-xd2000
         export MAKE_TARG2=gfortran-xd2000
      elif [ "$COMPILER" == "cray" ]; then
         export MAKE_TARG=cray-xd2000
         export MAKE_TARG2=cray-xd2000
      elif [ "$COMPILER" == "nvidia" ]; then
         export MAKE_TARG=nvhpc-xd2000
         export MAKE_TARG2=nvhpc-xd2000
      fi
      ;;
esac
# Make the same for other machines/systems...
echo "Host detected: $HOSTNAME"
echo "Compiler to be used: ${COMPILER}"

# Set unique key: scheduler + host:
export SYSTEM_KEY="${SCHEDULER_SYSTEM}_${HOSTNAME}"
export SYSTEM_KEYC="${SCHEDULER_SYSTEM}_${HOSTNAME}_${COMPILER}"


# Set environment variables and importants directories-------------------------------------------------- 


# MONAN-suite install root directories:
# Put your directories:
export DIR_SCRIPTS=$(dirname $(dirname $(pwd)))
export DIR_DADOS=${DIR_SCRIPTS}
# Fonte do MONAN: relativa a esta instalacao (scripts_CD-CT/sources), para o mesmo setenv.bash (no git)
# servir em qualquer pasta. O 1.install_monan.bash exporta MONAN_BRANCH/MONANDIR antes de carregar este arquivo.
export MONAN_BRANCH=${MONAN_BRANCH:-2.0.0-rc}
export MONANDIR=${MONANDIR:-${DIR_SCRIPTS}/scripts_CD-CT/sources/MONAN-Model_${MONAN_BRANCH}}


# Load your system setenv:
. ${DIR_SCRIPTS}/scripts_CD-CT/scripts/stools/setenv_${SYSTEM_KEYC}.bash

#module list
#echo ""
#read -p "Mostrando modulos carregados - Pressione Enter para continuar.... "
#echo ""


#-----------------------------------------------------------------------
# We discourage changing the variables below:

# Others variables:


# Colors:
#
export GREEN='\033[1;32m'  # Green
export RED='\033[1;31m'    # Red
export NC='\033[0m'        # No Color
export BLUE='\033[01;34m'  # Blue


# Functions: ======================================================================================================

# Python com numpy + eccodes: ICON_PYTHON se definido; senao o primeiro ambiente conda do usuario
# (ou o python3 do sistema) que importe os dois. Imprime o caminho; retorna 1 se nao achar.
# Uso geral: find_python "<modulos>" <VARIAVEL>, ex.: find_python "numpy, netCDF4, cartopy" PLOT_PYTHON
# (procura um Python que importe os modulos; a VARIAVEL, se definida, fixa o Python).
find_python () {
   local cand cands
   local mods=${1:-"numpy, eccodes"}
   local fixed=${ICON_PYTHON}
   if [ -n "${2}" ]; then fixed=${!2}; fi
   if [ -n "${fixed}" ]
   then
      cands="${fixed}"
   else
      cands="$(ls -d ${HOME}/.conda/envs/*/bin/python ${HOME}/miniconda3/envs/*/bin/python \
               ${HOME}/miniforge3/envs/*/bin/python ${HOME}/anaconda3/envs/*/bin/python \
               ${HOME}/miniconda3/bin/python ${HOME}/miniforge3/bin/python 2>/dev/null) $(command -v python3)"
   fi
   for cand in ${cands}
   do
      [ -x "${cand}" ] || continue
      if "${cand}" -c "import ${mods}" > /dev/null 2>&1
      then
         echo "${cand}"
         return 0
      fi
   done
   echo -e "${RED}==>${NC} No Python with ${mods} found (tried: ${cands})." >&2
   echo -e "${RED}==>${NC} Set ${2:-ICON_PYTHON}=<.../bin/python> in setenv.bash, or create a conda env with these modules." >&2
   return 1
}

# Nome da rodada (subpasta de dataout/LABELI e sufixo do run.LABELI): EXP ou EXP_RUN_TAG
run_name () {
   if [[ -n "${RUN_TAG}" && ! "${RUN_TAG}" =~ ^[A-Za-z0-9_.-]+$ ]]
   then
      echo "RUN_TAG must contain only letters, digits, '_', '.' or '-' (got '${RUN_TAG}')" >&2
      exit 1
   fi
   echo "${1}${RUN_TAG:+_${RUN_TAG}}"
}

how_many_nodes () { 
   nume=${1}   
   deno=${2}
   num=$(echo "${nume}/${deno}" | bc -l)  
   how_many_nodes_int=$(echo "${num}/1" | bc)
   dif=$(echo "scale=0; (${num}-${how_many_nodes_int})*100/1" | bc)
   rest=$(echo "scale=0; (((${num}-${how_many_nodes_int})*${deno})+0.5)/1" | bc -l)
   if [ ${dif} -eq 0 ]; then how_many_nodes_left=0; else how_many_nodes_left=1; fi
   if [ ${how_many_nodes_int} -eq 0 ]; then how_many_nodes_int=1; how_many_nodes_left=0; rest=0; fi
   how_many_nodes=$(echo "${how_many_nodes_int}+${how_many_nodes_left}" | bc )
   #echo "INT number of nodes needed: \${how_many_nodes_int}  = ${how_many_nodes_int}"
   #echo "number of nodes left:       \${how_many_nodes_left} = ${how_many_nodes_left}"
   echo "The number of nodes needed: \${how_many_nodes}  = ${how_many_nodes}"
   echo ""
}
#----------------------------------------------------------------------------------------------


