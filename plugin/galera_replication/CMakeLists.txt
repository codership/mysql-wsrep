# Copyright (C) 2022 Codership Oy <info@galeracluster.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2.0,
# as published by the Free Software Foundation.
#
# This program is also distributed with certain software (including
# but not limited to OpenSSL) that is licensed under separate terms,
# as designated in a particular file or component or in included license
# documentation.  The authors of MySQL hereby grant you an additional
# permission to link the program and your derivative works with the
# separately licensed software that they have included with MySQL.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License, version 2.0, for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

OPTION(WITH_GALERA "Build Galera library" OFF)
OPTION(GALERA_SHALLOW_CLONE "Use shallow clone for Galera" ON)

MESSAGE(STATUS "Building with Galera ${WITH_GALERA}")

IF(NOT WITH_GALERA)
  RETURN()
ENDIF()

IF (NOT GALERA_GIT_REPOSITORY)
  SET(GALERA_GIT_REPOSITORY
    "https://github.com/codership/galera.git"
    CACHE STRING "Galera git repository" FORCE)
ENDIF()
IF (NOT GALERA_BRANCH)
  SET(GALERA_BRANCH "origin/3.x"
    CACHE STRING "Galera branch, tag or commit" FORCE)
ENDIF()

IF (INSTALL_LAYOUT MATCHES "STANDALONE")
  SET(GALERA_STATIC_OPTION "-DGALERA_STATIC:BOOL=ON")
ELSE()
  SET(GALERA_STATIC_OPTION "")
ENDIF()

MESSAGE(STATUS "Galera git repository ${GALERA_GIT_REPOSITORY}")
MESSAGE(STATUS "Galera branch ${GALERA_BRANCH}")

INCLUDE(ExternalProject)
ExternalProject_Add(galera
  BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/galera
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/galera
  INSTALL_COMMAND ""
  GIT_REPOSITORY ${GALERA_GIT_REPOSITORY}
  GIT_TAG ${GALERA_BRANCH}
  GIT_SUBMODULES "wsrep/src"
  GIT_SHALLOW ${GALERA_SHALLOW_CLONE}
  GIT_REMOTE_UPDATE_STRATEGY CHECKOUT
  CMAKE_ARGS
  -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
  -DGALERA_WITH_ASAN:BOOL=${WITH_ASAN}
  -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
  -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
  -DCMAKE_COLOR_MAKEFILE:BOOL=${CMAKE_COLOR_MAKEFILE}
  ${GALERA_STATIC_OPTION}
  -DOPENSSL_ROOT_DIR=${OPENSSL_ROOT_DIR})
INSTALL(FILES
  "${CMAKE_CURRENT_BINARY_DIR}/galera/libgalera_smm.so"
  DESTINATION ${INSTALL_PLUGINDIR}
  COMPONENT Server)
INSTALL(PROGRAMS
  "${CMAKE_CURRENT_BINARY_DIR}/galera/garb/garbd"
  DESTINATION ${INSTALL_BINDIR}
  COMPONENT Server)
