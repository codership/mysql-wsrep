#!/usr/bin/env bash

CREATEREPO=yes
PRODUCT_SUFFIX="wsrep"
MYSQL_RPM_NAMES="mysql-wsrep-${MYSQL_VERSION} mysql-wsrep-test-${MYSQL_VERSION} gdb"
PROPFILE="mysql.properties"

if [[ ${label} =~ rhel-8 ]] || [[ ${label} =~ rhel-9 ]]; then
	RHELFIX='module_hotfixes=1'
fi

set -xe

if [[ -z ${WORKSPACE} ]]; then
  echo "Probably not Jenkins!"
  exit 1
fi

cd "${WORKSPACE}"

if [[ ! -f ${MYSQL_SOURCETAR:-} ]]; then
  export MYSQL_SOURCETAR=$(find . -type f -name mysql-wsrep-*.tar.gz)
fi

[[ -z "${MYSQL_SOURCETAR}" ]] && echo "No MYSQL_SOURCETAR found!" && exit 1

tar xf ${MYSQL_SOURCETAR} --strip-components=1 || exit 1

if [[ -f ${PROPFILE} ]]; then
  source ${PROPFILE}
fi
#
[[ -f VERSION ]] && source VERSION
[[ -f WSREP_VERSION ]] && source WSREP_VERSION
#
mkdir -p ${WORKSPACE}/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp -av ${MYSQL_SOURCETAR} ${WORKSPACE}/rpmbuild/SOURCES
cp -av ${WORKSPACE}/packaging/rpm-common/filter-*.sh ${WORKSPACE}/rpmbuild/SOURCES
rm -fv ${MYSQL_SOURCETAR}

pushd ${WORKSPACE}/rpmbuild/SOURCES
  BOOST_VERSION="1_59_0"
  [[ ! -f boost_${BOOST_VERSION}.tar.bz2 ]] && wget -q ${DEP_DL_URL}/boost_${BOOST_VERSION}.tar.bz2
  [[ ! -f mysql-5.6.51.tar.gz ]] &&  wget -q ${DEP_DL_URL}/mysql-5.6.51.tar.gz
popd

# Create spec file
export BUILDDIR=${WORKSPACE}/build

rm -fr ${BUILDDIR} && \
  mkdir ${BUILDDIR} && \
  cd ${BUILDDIR}

pushd /var/tmp
  cp -av ${WORKSPACE}/rpmbuild/SOURCES/boost_*.tar.bz2 .
popd

cmake \
  -DWITH_BOOST=/var/tmp -DDOWNLOAD_BOOST=1 \
  -DWITH_WSREP=1 \
  -DWSREP_VERSION=${MYSQL_WSREP_VERSION} \
  -DEXTRA_VERSION=-${MYSQL_WSREP_VERSION} \
  ../

if [[ "${MYSQL_ENTERPRISE:-}" = yes ]]; then
  PRODUCT_SUFFIX="wsrep-enterprise"
  MYSQL_RPM_NAMES="mysql-wsrep-enterprise-${MYSQL_VERSION} mysql-wsrep-enterprise-test gdb"
fi

echo "MYSQL_RPM_NAMES=\"${MYSQL_RPM_NAMES}\"" >> ${WORKSPACE}/${PROPFILE}

if [[ ${HOTFIX_BUILD:=false} = true ]]; then
  export PATH="/usr/bin:${PATH}"
else
  # Setup ccache on EFS
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
    [[ -h /usr/local/bin/cc ]]  && export CC="/usr/local/bin/cc"
    [[ -h /usr/local/bin/c++ ]] && export CXX="/usr/local/bin/c++"
  else
    ccache --set-config cache_dir=${EFS_MOUNTPOINT}/${JOB_NAME}
    ccache --set-config temporary_dir=/var/tmp/.ccache
  fi
  #
  ccache -M 8G
  ccache -sv
  ccache -z
fi
#
echo "No need to use devtoolset"
#
rpmbuild -bb --define "_topdir ${WORKSPACE}/rpmbuild" \
  --define "with_wsrep 1" \
  --define "product_suffix ${PRODUCT_SUFFIX}" \
  --define "release ${MYSQL_WSREP_VERSION}" packaging/rpm-oel/mysql.spec

[[ -f packaging/rpm-oel/mysql-wsrep.spec ]] && rpmbuild -bb --define "_topdir ${WORKSPACE}/rpmbuild" \
  packaging/rpm-oel/mysql-wsrep.spec

cd ${WORKSPACE}

# remove mysql-router package
find ${WORKSPACE}/rpmbuild/RPMS -type f -name "mysql-router*.rpm" -exec rm -fv {} \;

if [[ ${CREATEREPO} = yes ]]; then
  ARCH=$(arch)
  RHEL=$(rpm --eval '%rhel')
  mkdir -p ${WORKSPACE}/repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/redhat/${RHEL}/${ARCH}
  cp -av ${WORKSPACE}/rpmbuild/RPMS/${ARCH}/*  ${WORKSPACE}/repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/redhat/${RHEL}/${ARCH}
  createrepo -v ${WORKSPACE}/repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/redhat/${RHEL}/${ARCH}
cat << EOF > ${WORKSPACE}/mysql-wsrep.repo 
[${MYSQL_REPO_NAME}]
name=MySQL WSREP ${MYSQL_VERSION} ${MYSQL_GIT_COMMIT}
baseurl=${MYSQL_S3_URL}/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/redhat/${RHEL}/${ARCH}
gpgcheck=0
enabled=1
${RHELFIX:-}
EOF
fi
#
ccache -sv
#
