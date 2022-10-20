#!/usr/bin/env bash

CREATEREPO=yes
PROPFILE="mysql.properties"
CMAKE_EXTRA_OPTIONS=""

set -xe

if [[ -z ${WORKSPACE} ]]; then
  echo "Probably not Jenkins!"
  exit 1
fi

cd "${WORKSPACE}"
rm -fv ${MYSQL_SOURCETAR}

if [[ -f ${WORKSPACE}/${PROPFILE} ]]; then
  source ${WORKSPACE}/${PROPFILE}
else
  [[ -f VERSION ]] && . VERSION
  [[ -f WSREP_VERSION ]] && . WSREP_VERSION
  export MYSQL_VERSION="${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}"
  export MYSQL_VERSION_FULL=${MYSQL_VERSION}.${MYSQL_VERSION_PATCH}
  export WSREP_VERSION="${WSREP_VERSION_API}.${WSREP_VERSION_PATCH}"
fi

# Create Build directory
export BUILDDIR=${WORKSPACE}/build

rm -fr ${BUILDDIR} && \
  mkdir ${BUILDDIR} && \
  cd ${BUILDDIR}

if [[ ${HOTFIX_BUILD:=false} = true ]]; then
  export PATH="/usr/bin:${PATH}"
else
  #
  # Setup ccache on EFS only for regular builds
  # don't need to mount EFS, it's automatic. need to wait a bit (sometimes)
  #
  EFS_MOUNTPOINT=/mnt/efs/ccache
  #
  for _try in {0..30}; do
    sleep ${_try}
    test -d "${EFS_MOUNTPOINT}" && break
  done
  #
  ls -la "${EFS_MOUNTPOINT}"
  sudo chmod 777 "${EFS_MOUNTPOINT}"

  if ccache -p | grep secondary_storage; then
    ccache --set-config secondary_storage=file:${EFS_MOUNTPOINT}/${JOB_NAME}
    [[ -h /usr/local/bin/cc ]]  && export CC=/usr/local/bin/cc
    [[ -h /usr/local/bin/c++ ]] && export CXX=/usr/local/bin/c++
  else
    ccache --set-config cache_dir="${EFS_MOUNTPOINT}/${JOB_NAME}"
    ccache --set-config temporary_dir=/var/tmp/.ccache/tmp
  fi
  ccache -M 8G
  ccache -z
fi
#
# Download boost
pushd /var/tmp
  BOOST_VERSION="1_59_0"
  [[ ! -f boost_${BOOST_VERSION}.tar.bz2 ]] && wget -q ${DEP_DL_URL}/boost_${BOOST_VERSION}.tar.bz2
popd
#
if [[ ${BUILD_TYPE:-RelWithDebInfo} = RelWithDebInfo ]]; then
  CMAKE_EXTRA_OPTIONS+=' -DBUILD_CONFIG=mysql_release'
  CMAKE_EXTRA_OPTIONS+=' -DWITH_INNODB_MEMCACHED=1'
fi
#
/usr/local/bin/cmake ../ \
-DCMAKE_BUILD_TYPE=${BUILD_TYPE:-RelWithDebInfo} \
-DWITH_WSREP:BOOL=ON -DWSREP_VERSION=${MYSQL_WSREP_VERSION} \
-DDOWNLOAD_BOOST=1 -DWITH_BOOST=/var/tmp \
-DWITH_SSL=/usr/local/OpenSSL -DWITH_ZLIB=bundled \
-DWITH_LIBEVENT=bundled -DWITH_ROUTER:BOOL=OFF \
-DWITH_EXTRA_CHARSETS=all ${CMAKE_EXTRA_OPTIONS:-}

NCPU=$(grep -c proc /proc/cpuinfo)

make -j${NCPU} VERBOSE=1
make package

mv -vf ${BUILDDIR}/*.tar.gz ${WORKSPACE}
cd ${WORKSPACE}

MYSQL_BINTAR=$(basename $(find ${WORKSPACE} -mindepth 1 -maxdepth 1 -name "mysql-wsrep-*.tar.gz"))
echo "MYSQL_BINTAR=${MYSQL_BINTAR}" >> ${PROPFILE}
echo "MYSQL_BINTAR_URL=${MYSQL_S3_URL}/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/binary/${BINTAR}" >> ${PROPFILE}

if [[ ${CREATEREPO} = yes ]]; then
  mkdir -p ${WORKSPACE}/repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/binary/${BUILD_TYPE}
  cp ${WORKSPACE}/${MYSQL_BINTAR} ${WORKSPACE}/repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/binary/${BUILD_TYPE}
fi
#
ccache -sv
#
