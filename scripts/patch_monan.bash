#!/bin/bash
umask 022
#-----------------------------------------------------------------------------#
# !SCRIPT: patch_monan
#
# !DESCRIPTION:
#     Correcoes no codigo-fonte do MONAN (${MONANDIR}). O 1.install_monan.bash
#     aplica antes de compilar. Rodar de novo e seguro (o que ja foi corrigido
#     nao e mexido).
#
#     1) init_atmosphere: u10, v10, t2m e q2 absurdos (~ -1e30) em +0 h com ICON/IFS.
#        Em mpas_init_atm_cases.F, a interpolacao desses campos de superficie da CI
#        para os centros das celulas so corrige a longitude quando x < 0.5
#        (lon + 360), e nao quando x > nx (lon - 360), como fazem os campos 3D.
#        O map_set poe a longitude inicial do recorte em [-180, 180] (ex.: -95) e
#        o lonCell da malha esta em [0, 360) (ex.: 300): x cai depois do fim do
#        recorte e o SEARCH devolve -1e30. Com o GFS global (lon1 = 0) nao acontece.
#        So afeta a saida de +0 h: a partir do primeiro passo a camada superficial
#        recalcula esses campos.
#
# !CALLING SEQUENCE:
#     ./patch_monan.bash          so aplica as correcoes no fonte
#     ./patch_monan.bash init     aplica e recompila so o init_atmosphere_model
#                                 (vai para execs/; nao precisa reinstalar tudo)
#-----------------------------------------------------------------------------#

. setenv.bash > /dev/null

DIRHOMED=${DIR_DADOS}/scripts_CD-CT
EXECS=${DIRHOMED}/execs

if [ ! -d "${MONANDIR}/src" ]
then
   echo -e "${RED}==>${NC} MONAN source not found in ${MONANDIR}. Run 1.install_monan.bash first."
   exit 1
fi


# 1) u10/v10/t2m/q2 da CI: correcao da longitude tambem para x > nx ---------------------
src=${MONANDIR}/src/core_init_atmosphere/mpas_init_atm_cases.F
mark="patch_monan: lon - 360 tambem na superficie"
if grep -q "${mark}" ${src}
then
   echo -e "${GREEN}==>${NC} $(basename ${src}): u10/v10/t2m/q2 longitude fix already applied."
else
   # Unico trecho: "if (x < 0.5) ... lon + 360 ... end if" logo antes do
   # "destField1d(i) = interp_sequence(..., &" do bloco de superficie
   awk -v mark="${mark}" '
      NR > 1 {
         if ($0 ~ /destField1d\(i\) = interp_sequence\(x, y, 1, rslab, -2, field % nx \+ 3, 1, field % ny, 1, 1, &$/ &&
             prev ~ /^ *end if *$/ && p2 ~ /call latlon_to_ij\(proj, lat, lon, x, y\)/ && p3 ~ /lon = lon \+ 360\.0/) {
            ind = prev; sub(/end if *$/, "", ind)
            print ind "else if (x >= real(field % nx) + 0.5) then   ! " mark
            print ind "   lon = lon - 360.0"
            print ind "   call latlon_to_ij(proj, lat, lon, x, y)"
            n++
         }
         print prev
      }
      { p3 = p2; p2 = prev; prev = $0 }
      END { print prev; exit (n == 1 ? 0 : 1) }
   ' ${src} > ${src}.patch_monan
   if [ $? -ne 0 ]
   then
      rm -f ${src}.patch_monan
      echo -e "${RED}==>${NC} $(basename ${src}): code block not found (MONAN version changed?). Not patched."
      exit 1
   fi
   cat ${src}.patch_monan > ${src} && rm -f ${src}.patch_monan
   echo -e "${GREEN}==>${NC} $(basename ${src}): u10/v10/t2m/q2 longitude fix applied."
fi
#-----------------------------------------------------------------------------------------


# Recompilar so o init_atmosphere (como no make-all.sh do 1.install_monan.bash)
if [[ ${1} == "init" ]]
then
   echo -e "\n${GREEN}==>${NC} Building init_atmosphere_model (${MAKE_TARG2})...\n"
   cd ${MONANDIR}
   export NETCDF=${NETCDFDIR}
   export PNETCDF=${PNETCDFDIR}
   export PIO=
   rm -fr ${MONANDIR}/src/core_init_atmosphere/inc
   MAKE_OUT_FILE="make_$(date +"%Y%m%d%H%M%S")_.output.init_atmosphere"
   make clean CORE=init_atmosphere > /dev/null
   make -j 8 ${MAKE_TARG2} CORE=init_atmosphere OPENMP=true USE_PIO2=false PRECISION=single 2>&1 | tee ${MAKE_OUT_FILE}
   if [ ! -s ${MONANDIR}/init_atmosphere_model ]
   then
      echo -e "\n${RED}==>${NC} Build failed. Check ${MONANDIR}/${MAKE_OUT_FILE}"
      exit 1
   fi
   mv ${MONANDIR}/init_atmosphere_model ${EXECS}
   make clean CORE=init_atmosphere > /dev/null
   echo -e "\n${GREEN}==>${NC} ${EXECS}/init_atmosphere_model rebuilt. Run 2.pre_processing.bash again (and the model).\n"
fi
