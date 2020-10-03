#!/usr/bin/env bash

echo "Build Linux arm MuseScore AppImage"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -n|--number) BUILD_NUMBER="$2"; shift ;;
        --telemetry) TELEMETRY_TRACK_ID="$2"; shift ;;
        --arch) ARCH="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$BUILD_NUMBER" ]; then echo "error: not set BUILD_NUMBER"; exit 1; fi
if [ -z "$TELEMETRY_TRACK_ID" ]; then TELEMETRY_TRACK_ID=""; fi
if [ -z "$ARCH" ]; then ARCH=""; fi

echo "BUILD_NUMBER: $BUILD_NUMBER"

echo "=== ENVIRONMENT === "

export PATH=/qt5/bin/:$PATH
export CMAKE_TOOLCHAIN_FILE="/MuseScore/build/ci/linux_arm/crosscompile-$ARCH.cmake"
if [ "$ARCH" == "armhf" ]
then
  export LIBARM="/lib/arm-linux-gnueabihf"
elif [ "$ARCH" == "arm64" ]
then
  export LIBARM="/lib/aarch64-linux-gnu"
fi



export LD_LIBRARY_PATH="/usr$LIBARM:/usr$LIBARM/alsa-lib:/usr$LIBARM/pulseaudio:$LIBARM:/qt5/lib:/usr/lib"

# Create two empty files since qcollectiongenerator and qhelpgenerator are not generated
# during cross-compilation
touch /qt5/bin/qcollectiongenerator
touch /qt5/bin/qhelpgenerator

# remove old CMake
apt-get remove -y cmake
cd /
wget https://github.com/Kitware/CMake/releases/download/v3.17.5/cmake-3.17.5-Linux-x86_64.tar.gz
tar -zxf cmake-3.17.5-Linux-x86_64.tar.gz 
export PATH=/cmake-3.17.5-Linux-x86_64/bin:$PATH

echo " "
echo "PATH=$PATH"
echo " "
${CXX} --version 
${CC} --version
echo " "
cmake --version
echo " "

echo "=== BUILD === "

cd /MuseScore

make revision
make BUILD_NUMBER=$BUILD_NUMBER TELEMETRY_TRACK_ID=$TELEMETRY_TRACK_ID portable

# Hack: create a new qmake and new qmlimportscanner which will be used in the arm virtual machine
# since the original qmake and qmlimportscanner are x86_64 executables
cd build.release/
echo $'#!/bin/bash\n'echo \""$(qmake -query)"\" >qmakenew
chmod +x qmakenew
prefix="$(cat ./PREFIX.txt)" # MuseScore was installed here
appdir="$(basename "${prefix}")" # directory that will become the AppImage
qmlimportscanner  -rootPath  "${appdir}"  -importPath  /qt5/qml >qmlimportscannerfile
echo $'#!/bin/bash\n'cat /qt5/bin/qmlimportscannerfile >qmlimportscannernew
chmod +x qmlimportscannernew 
cd ..

# Prepare for artifacts upload
mkdir build.artifacts
mkdir build.artifacts/env

bash ./build/ci/tools/make_release_channel_env.sh 
bash ./build/ci/tools/make_version_env.sh $BUILD_NUMBER
bash ./build/ci/tools/make_revision_env.sh
