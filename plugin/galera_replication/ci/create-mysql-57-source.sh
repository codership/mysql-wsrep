#!/usr/bin/env bash
#
CREATEREPO=yes
PROPFILE="mysql.properties"
#
set -xe
#
if [[ -z ${WORKSPACE} ]]; then
  echo "Probably not Jenkins"
  exit 1
fi
#
cd "${WORKSPACE}"
#
git reset --hard
git clean -xffd
git submodule update --init --recursive
# hotfix?
if [[ ${HOTFIX_BUILD:-false} = true ]]; then
  BUILD_TIMESTAMP=$(date +%Y%m%d)
  BUILD_HASH=$(git log --format="%h" -n1)
  HOTFIX_VERSION_EXTRA=".${BUILD_TIMESTAMP}.${BUILD_HASH}"
fi
#
[[ -f VERSION ]] && source VERSION
[[ -f WSREP_VERSION ]] && source WSREP_VERSION

[[ -z "${GIT_BRANCH}" ]] && export GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ -z "${GIT_COMMIT}" ]] && export GIT_COMMIT=$(git rev-parse HEAD)
MYSQL_VERSION="${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}"
MYSQL_VERSION_FULL="${MYSQL_VERSION}.${MYSQL_VERSION_PATCH}"
MYSQL_WSREP_VERSION="${WSREP_VERSION_API}.${WSREP_VERSION_PATCH}${HOTFIX_VERSION_EXTRA:-}"
#
# Create Build directory
export BUILDDIR=${WORKSPACE}/build
#
rm -fr ${BUILDDIR} && mkdir ${BUILDDIR}
pushd ${BUILDDIR}
#
  cmake ../ \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DWITH_WSREP:BOOL=ON -DDOWNLOAD_BOOST=1 \
  -DWITH_BOOST=/var/tmp -DWITH_SSL=system \
  -DWSREP_VERSION=${MYSQL_WSREP_VERSION}
  #
  make dist
popd
mv -vf ${BUILDDIR}/*.tar.gz ${WORKSPACE}
#
MYSQL_SOURCETAR=$(find ${WORKSPACE} -mindepth 1 -maxdepth 1 -name "mysql-wsrep*${MYSQL_VERSION_FULL}-${MYSQL_WSREP_VERSION}.tar.gz" | xargs basename)
#
MYSQL_REPO_NAME="mysql-wsrep-${MYSQL_VERSION_FULL}-${MYSQL_WSREP_VERSION}"
if [[ "${ENTERPRISE:-}" = yes ]]; then
  echo "MYSQL_ENTERPRISE=yes" >> ${WORKSPACE}/${PROPFILE}
  MYSQL_REPO_NAME="mysql-wsrep-enterprise-${MYSQL_VERSION_FULL}-${MYSQL_WSREP_VERSION}"
fi
#
echo "MYSQL_GIT_BRANCH=${GIT_BRANCH}" >> ${WORKSPACE}/${PROPFILE}
echo "MYSQL_GIT_COMMIT=${GIT_COMMIT}" >> ${WORKSPACE}/${PROPFILE}
echo "MYSQL_VERSION=${MYSQL_VERSION}" >> ${WORKSPACE}/${PROPFILE}
echo "MYSQL_VERSION_FULL=${MYSQL_VERSION_FULL}" >> ${WORKSPACE}/${PROPFILE}
echo "MYSQL_WSREP_VERSION=${MYSQL_WSREP_VERSION}" >> ${WORKSPACE}/${PROPFILE}
echo "MYSQL_S3_URL=${MYSQL_S3_URL}" >> ${WORKSPACE}/${PROPFILE}
echo "MYSQL_SOURCETAR=${MYSQL_SOURCETAR}" >> ${WORKSPACE}/${PROPFILE}
echo "MYSQL_SOURCEURL=${MYSQL_S3_URL}/${MYSQL_REPO_NAME}/${GIT_COMMIT}/source/${MYSQL_SOURCETAR}" >> ${WORKSPACE}/${PROPFILE}
echo "MYSQL_REPO_NAME=${MYSQL_REPO_NAME}" >> ${WORKSPACE}/${PROPFILE}
#
source ${WORKSPACE}/${PROPFILE}
#
if [[ ${CREATEREPO} = yes ]]; then
  mkdir -p ${WORKSPACE}/repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/source
  cp ${WORKSPACE}/${MYSQL_SOURCETAR} ${WORKSPACE}/repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/source
fi
