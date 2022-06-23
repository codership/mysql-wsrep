#!/usr/bin/env bash

CREATEREPO=yes
PROPFILE="mysql.properties"

CODENAME=$(lsb_release -sc)
#
case ${CODENAME} in
  xenial | bionic | buster)
    DEB_SYSTEMD_OPTS="-DWITH_SYSTEMD=1 -DSYSTEMD_SERVICE_NAME=\"mysql\""
  ;;
  jammy)
  LIBFIDO_OPTION="-DWITH_FIDO=system"
  ;;
esac

set -xe

if [[ -z ${WORKSPACE} ]]; then
  echo "Probably not a Jenkins!"
  exit 1
fi

cd "${WORKSPACE}"

rm -fr ${DEB_BUILDDIR} && mkdir -p ${DEB_BUILDDIR}
rm -fv ${MYSQL_SOURCETAR}

if [[ -f ${PROPFILE} ]]; then
  . ${PROPFILE}
else
  [[ -f VERSION ]] && . VERSION
  [[ -f WSREP_VERSION ]] && . WSREP_VERSION
  export MYSQL_VERSION="${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}"
  export MYSQL_VERSION_FULL=${MYSQL_VERSION}.${MYSQL_VERSION_PATCH}
  export MYSQL_WSREP_VERSION="${WSREP_VERSION_API}.${WSREP_VERSION_PATCH}"
fi

if [[ -n "${WORKSPACE}" ]]; then
  pushd /var/tmp
    BOOST_VERSION="1_59_0"
    [[ ! -f boost_${BOOST_VERSION}.tar.bz2 ]] && wget -q ${DEP_DL_URL}/boost_${BOOST_VERSION}.tar.bz2 
  # Cmake run from debian build scripts looks up boost package from /tmp
    cp boost*.tar.* /tmp
  popd
fi

cd ${DEB_BUILDDIR}

# Create spec file
export CMAKEBUILDDIR=${DEB_BUILDDIR}/build

rm -fr ${CMAKEBUILDDIR} && \
mkdir -p ${CMAKEBUILDDIR}

pushd ${CMAKEBUILDDIR}
  MYSQL_DEB_NAMES="mysql-wsrep-${MYSQL_VERSION} mysql-wsrep-server-${MYSQL_VERSION} mysql-wsrep-test-${MYSQL_VERSION}"
  cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_VERBOSE_MAKEFILE=ON -DMYSQL_UNIX_ADDR=/var/run/mysqld/mysqld.sock \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_CONFIG=mysql_release ${DEB_SYSTEMD_OPTS:-} \
    -DWITH_WSREP=1 -DWITH_LIBWRAP=ON -DWITH_ZLIB=system -DWITH_SSL=system -DWITH_MECAB=system \
    -DDOWNLOAD_BOOST=1 -DWITH_BOOST=/var/tmp -DCOMPILATION_COMMENT="(Ubuntu)" \
    -DMYSQL_SERVER_SUFFIX="-1" -DINSTALL_LAYOUT=DEB -DINSTALL_DOCDIR=share/mysql/docs \
    -DINSTALL_DOCREADMEDIR=share/mysql -DINSTALL_INCLUDEDIR=include/mysql -DINSTALL_INFODIR=share/mysql/docs \
    -DINSTALL_LIBDIR=lib/x86_64-linux-gnu -DINSTALL_MANDIR=share/man -DINSTALL_MYSQLSHAREDIR=share/mysql \
    -DINSTALL_MYSQLTESTDIR=lib/mysql-test -DINSTALL_PLUGINDIR=lib/mysql/plugin -DINSTALL_SBINDIR=sbin \
    -DINSTALL_SCRIPTDIR=bin -DINSTALL_SUPPORTFILESDIR=share/mysql -DSYSCONFDIR=/etc/mysql \
    -DWITH_ARCHIVE_STORAGE_ENGINE=ON -DWITH_BLACKHOLE_STORAGE_ENGINE=ON -DWITH_FEDERATED_STORAGE_ENGINE=ON \
    -DWITH_INNODB_MEMCACHED=1 -DWITH_EXTRA_CHARSETS=all -DWSREP_VERSION=${MYSQL_WSREP_VERSION} \
    -DDEB_CMAKE_EXTRAS="-DWSREP_VERSION=${MYSQL_WSREP_VERSION}" \
    ../
popd

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
  #
  if ccache -p | grep secondary_storage; then
    ccache --set-config secondary_storage=file:${EFS_MOUNTPOINT}/${JOB_NAME}
    [[ -h /usr/local/bin/cc ]]  && export CC=/usr/local/bin/cc
    [[ -h /usr/local/bin/c++ ]] && export CXX=/usr/local/bin/c++
  else
    ccache --set-config cache_dir=${EFS_MOUNTPOINT}/${JOB_NAME}
    ccache --set-config temporary_dir=/var/tmp/.ccache
  fi
  #
  ccache -M 8G
  ccache -z
  #
fi
#
cp -av ${CMAKEBUILDDIR}/debian ${DEB_BUILDDIR}
# TODO Jammy hack for libfido2
if [[ ${CODENAME} = jammy ]]; then
  grep 'libfido2' ${DEB_BUILDDIR}/debian/*.install && \
  sed -i 's:^.*libfido2.*::g' ${DEB_BUILDDIR}/debian/*.install
fi
#
cd ${DEB_BUILDDIR}
export DEB_BUILD_OPTIONS="nocheck nostrip"
export MYSQL_BUILD_MAKE_JFLAG="-j$(grep -c proc /proc/cpuinfo)"

dpkg-buildpackage -b -us -uc

cd ${WORKSPACE}

echo "MYSQL_DEB_NAMES=\"${MYSQL_DEB_NAMES}\"" >> ${WORKSPACE}/${PROPFILE}

# create repository
ARCH=$(dpkg --print-architecture)
#
mkdir -p ${WORKSPACE}/repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/deb/${CODENAME}/${ARCH}
cp -av mysql-*.* libmysql* ${WORKSPACE}/repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/deb/${CODENAME}/${ARCH}

pushd repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/deb/${CODENAME}
  dpkg-scanpackages ${ARCH} /dev/null | gzip -9c > ${ARCH}/Packages.gz
popd

cat << EOF > ${WORKSPACE}/mysql-wsrep.list
deb [trusted=yes] ${MYSQL_S3_URL}/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/deb/${CODENAME} ${ARCH}/
EOF
#
ccache -sv
#
