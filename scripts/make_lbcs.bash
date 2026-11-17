#!/bin/bash 

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
   echo ""
   exit
fi

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash

echo ""
echo "---- Make LBCs ----"
echo ""


# Standart directories variables:---------------------------------------
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
start_date=${YYYYMMDDHHi:0:4}-${YYYYMMDDHHi:4:2}-${YYYYMMDDHHi:6:2}_${YYYYMMDDHHi:8:2}:00:00
yyyymmddi=${YYYYMMDDHHi:0:8}
hhi=${YYYYMMDDHHi:8:2}
yyyymmddhhf=$(date +"%Y%m%d%H" -d "${yyyymmddi} ${hhi}:00 ${FCST} hours" )
final_date=${yyyymmddhhf:0:4}-${yyyymmddhhf:4:2}-${yyyymmddhhf:6:2}_${yyyymmddhhf:8:2}:00:00
GEODATA=${DATAIN}/WPS_GEOG
cores=${LBCS_ncores}
export DIRRUN=${DIRHOMED}/run.${YYYYMMDDHHi}.${RUNNAME}; rm -fr ${DIRRUN}; mkdir -p ${DIRRUN}
#-------------------------------------------------------
mkdir -p ${OUTRUN}/Pre/logs

if [ ! -s ${DATAIN}/fixed/x1.${RES}.graph.info.part.${cores} ]
then
   if [ ! -s ${DATAIN}/fixed/x1.${RES}.graph.info ]
   then
      cd ${DATAIN}/fixed
      echo -e "${GREEN}==>${NC} downloading meshes tgz files ... \n"
      cd ${DATAIN}/fixed
      wget https://www2.mmm.ucar.edu/projects/mpas/atmosphere_meshes/x1.${RES}.tar.gz
      tar -xzvf x1.${RES}.tar.gz
   fi
   echo -e "${GREEN}==>${NC} Creating x1.${RES}.graph.info.part.${cores} ... \n"
   cd ${DATAIN}/fixed
   gpmetis -minconn -contig -niter=200 x1.${RES}.graph.info ${cores}
   rm -fr x1.${RES}.tar.gz
fi

files_needed=("${SCRIPTS}/namelists/namelist.init_atmosphere.LBCS" "${SCRIPTS}/namelists/streams.init_atmosphere.LBCS" "${DATAIN}/fixed/x1.${RES}.graph.info.part.${cores}" "${OUTRUN}/Pre/x1.${RES}.init.nc" "${EXECS}/init_atmosphere_model")
for file in "${files_needed[@]}"
do
  if [ ! -s "${file}" ]
  then
    echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"	  
    echo -e  "${RED}==>${NC} [${0}] At least the file ${file} was not generated. \n"
    exit -1
  fi
done

# As LBCs usam o zgrid do x1.${RES}.init.nc; so o numero de niveis precisa ser o mesmo
NVERTLEV=${NVERTLEV:?NVERTLEV not set in setenv.bash}
sed -e "s,#LABELI#,${start_date},g;s,#LABELF#,${final_date},g;s,#GEODAT#,${GEODATA},g;s,#LBCINT#,${LBCINT},g;s,#RES#,${RES},g;s,#EXP#,${EXP},g;s,#NVERTLEV#,${NVERTLEV},g" \
	 ${SCRIPTS}/namelists/namelist.init_atmosphere.LBCS > ${DIRRUN}/namelist.init_atmosphere

sed -e "s,#RES#,${RES},g;s,#LBCINT#,${LBCINT},g" \
    ${SCRIPTS}/namelists/streams.init_atmosphere.LBCS > ${DIRRUN}/streams.init_atmosphere

cp -f ${DATAIN}/fixed/x1.${RES}.graph.info.part.${cores} ${DIRRUN}
cp -f ${OUTRUN}/Pre/x1.${RES}.init.nc ${DIRRUN}
cp -f ${OUTRUN}/Pre/${EXP}\:* ${DIRRUN}
cp -f ${EXECS}/init_atmosphere_model ${DIRRUN}

cp -f ${SCRIPTS}/setenv.bash ${DIRRUN}
rm -f ${DIRRUN}/lbcs.bash 

if [ ${SCHEDULER_SYSTEM} != "GENERIC" ]
then
   sed -e "s,#JOBNAME#,${LBCS_jobname},g;
   s,#NNODES#,${LBCS_nnodes},g;
   s,#NCPUS#,${LBCS_ncpus},g;
   s,#NTASKS#,${LBCS_ncores},g;
   s,#NTASKSPNODE#,${LBCS_ncpn},g;
   s,#NTHREADS#,${LBCS_nthreads},g;
   s,#PARTITION#,${LBCS_QUEUE},g;
   s,#WALLTIME#,${LBCS_walltime},g;
   s,#OUTPUTJOB#,${OUTRUN}/Pre/logs/lbcs.o,g;
   s,#ERRORJOB#,${OUTRUN}/Pre/logs/lbcs.e,g" \
   ${SCRIPTS}/stools/submit_${SYSTEM_KEY}.bash_TEMPLATE > ${DIRRUN}/lbcs.bash 
else
   echo "#!/bin/bash " > ${DIRRUN}/lbcs.bash 
fi

cat << EOF0 >> ${DIRRUN}/lbcs.bash 

export executable=init_atmosphere_model

ulimit -c unlimited
ulimit -v unlimited
ulimit -s unlimited

. ${SCRIPTS}/setenv.bash

cd ${DIRRUN}

if [ ${SCHEDULER_SYSTEM} == "SLURM" ]; then
   echo "-- SLURM_JOB_ID: \$SLURM_JOB_ID"
   time mpirun -np ${LBCS_ncores} ./\${executable}
elif [ ${SCHEDULER_SYSTEM} == "PBS" ]; then
   echo "-- PBS_JOBID: \$PBS_JOBID"
   time mpirun --ppn ${LBCS_ncpn} -np ${LBCS_ncores} --depth=${LBCS_nthreads} --cpu-bind depth ./\${executable}
fi

date

mv ${DIRRUN}/log.init_atmosphere.0000.out ${OUTRUN}/Pre/logs/log.init_atmosphere.0000.${RES}.lbcs.nc.${YYYYMMDDHHi}.out
mv ${DIRRUN}/namelist.init_atmosphere ${OUTRUN}/Pre/logs/namelist.init_atmosphere.lbcs
mv ${DIRRUN}/streams.init_atmosphere ${OUTRUN}/Pre/logs/streams.init_atmosphere.lbcs
mv ${DIRRUN}/x1.${RES}.init.nc ${OUTRUN}/Pre
mv ${DIRRUN}/lbc*.nc ${OUTRUN}/Pre

EOF0

chmod a+x ${DIRRUN}/lbcs.bash

case "${SCHEDULER_SYSTEM}" in
   SLURM)
      echo -e  "\n${GREEN}==>${NC} sbatch lbcs.bash...\n"
      cd ${DIRRUN}
      sbatch --wait ${DIRRUN}/lbcs.bash
      ;;
    PBS)
      echo -e  "\n${GREEN}==>${NC} qsub lbcs.bash...\n"
      cd ${DIRRUN}
      JOBID=$(qsub -W block=true ${DIRRUN}/lbcs.bash)
      JOBID=${JOBID%%.*}
      mv ${OUTRUN}/Pre/logs/lbcs.o ${OUTRUN}/Pre/logs/lbcs.o.${JOBID}
      mv ${OUTRUN}/Pre/logs/lbcs.e ${OUTRUN}/Pre/logs/lbcs.e.${JOBID}
      ;;
#    GENERIC)
#      echo "Nenhum gerenciador detectado"
#      cd ${DIRRUN}
#      ${DIRRUN}/lbcs.bash
#      ;;
esac
mv ${DIRRUN}/lbcs.bash ${OUTRUN}/Pre/logs

if [ -z "$(ls ${OUTRUN}/Pre/lbc* 2>/dev/null)" ]
then
  echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"	
  echo -e  "${RED}==>${NC} LBC phase fails! Check logs at ${OUTRUN}/Pre/logs/lbcs.* .\n"
  echo -e  "${RED}==>${NC} Exiting script. \n"
  exit -1
fi

chmod -R 755 ${OUTRUN}/Pre/*
rm -fr ${DIRRUN}
