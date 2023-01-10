#!/usr/bin/env bash

PROPFILE="mysql.properties"
#
sudo pkg upgrade -y
#
# Setup ccache on EFS only for regular builds (not for hotfix)
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
else
  ccache --set-config cache_dir=${EFS_MOUNTPOINT}/${JOB_NAME}
  ccache --set-config temporary_dir=/var/tmp/.ccache
fi
#
ccache -M 8G
ccache -sv
ccache -z
#
cat << EOF | sudo tee /etc/make.conf
WITH_CCACHE_BUILD=yes
CC=/usr/local/bin/cc
CXX=/usr/local/bin/c++
EOF
#
sudo git clone --depth=1 https://git.freebsd.org/ports.git /usr/ports
if [ -f ${WORKSPACE}/mysqlwsrep57-server.patch ]; then
  pushd /usr/ports
  sudo patch -p1 < ${WORKSPACE}/mysqlwsrep57-server.patch
  popd
fi
sudo mkdir -p /usr/ports/distfiles
sudo mv -vf ${MYSQL_SOURCETAR} /usr/ports/distfiles
curl ${DEP_DL_URL}/boost_1_59_0.tar.gz > boost_1_59_0.tar.gz
sudo mv -vf boost_1_59_0.tar.gz /usr/ports/distfiles
#
sudo make -C /usr/ports/databases/mysqlwsrep57-server makesum depends
#
DISTFILES=${MYSQL_SOURCETAR} \
DISTNAME=dummy \
WRKSRC=\${WRKDIR}/${MYSQL_SOURCETAR%.tar.gz} \
sudo -E make -C /usr/ports/databases/mysqlwsrep57-server deinstall clean makesum stage check-orphans package
find /usr/ports/databases/mysqlwsrep57-server -name '*.pkg' -exec cp -v '{}' ${WORKSPACE} \;
#
MYSQL_PKG=$(find . -mindepth 1 -maxdepth 1 -name '*.pkg' | xargs basename )
echo "MYSQL_PKG=${MYSQL_PKG}" >> ${PROPFILE}
echo "MYSQL_PKG_URL=${MYSQL_S3_URL}/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/freebsd/${BUILD_TYPE:=RelWithDebInfo}/${MYSQL_PKG}" >> ${PROPFILE}
#
mkdir -p repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/freebsd/${BUILD_TYPE}
cp ${MYSQL_PKG} repo/${MYSQL_REPO_NAME}/${MYSQL_GIT_COMMIT}/freebsd/${BUILD_TYPE}
#
ccache -s
#
