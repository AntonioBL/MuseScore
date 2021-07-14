#!/usr/bin/env bash

echo "Package MuseScore"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --arch) ARCH="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$ARCH" ]; then ARCH=""; fi

ARTIFACTS_DIR="build.artifacts"

echo "=== ENVIRONMENT === "


# Hack: qmake and qmlimportscanner were compiled for x86_64
mv /qt5/bin/qmake /qt5/bin/qmakeold
mv /qt5/bin/qmlimportscanner /qt5/bin/qmlimportscannerold
mv /MuseScore/build.release/qmakenew /qt5/bin/qmake
mv /MuseScore/build.release/qmlimportscannernew /qt5/bin/qmlimportscanner
mv /MuseScore/build.release/qmlimportscannerfile /qt5/bin/qmlimportscannerfile

export PATH=/qt5/bin:/tools:/usr/local/bin:$PATH
if [ "$ARCH" == "armhf" ]
then
  export LIBARM="/lib/arm-linux-gnueabihf"
elif [ "$ARCH" == "arm64" ]
then
  export LIBARM="/lib/aarch64-linux-gnu"
fi
export LD_LIBRARY_PATH="/usr$LIBARM:/usr$LIBARM/alsa-lib:/usr$LIBARM/pulseaudio:$LIBARM:/qt5/lib:/usr/lib"
export QT_PATH=/qt5

cd /MuseScore

echo " "
echo "PATH=$PATH"
echo " "
appimagetool --version
echo " "
linuxdeploy --list-plugins
echo "===================="


##########################################################################
# BUNDLE DEPENDENCIES INTO APPDIR
##########################################################################

prefix="$(cat build.release/PREFIX.txt)" # MuseScore was installed here
cd "$(dirname "${prefix}")"
appdir="$(basename "${prefix}")" # directory that will become the AppImage

# Prevent linuxdeploy setting RUNPATH in binaries that shouldn't have it
mv "${appdir}/bin/findlib" "${appdir}/../findlib"

# Colon-separated list of root directories containing QML files.
# Needed for linuxdeploy-plugin-qt to scan for QML imports.
# Qml files can be in different directories, the qmlimportscanner will go through everything recursively.
export QML_SOURCES_PATHS=./

linuxdeploy --appdir "${appdir}" # adds all shared library dependencies
linuxdeploy-plugin-qt --appdir "${appdir}" # adds all Qt dependencies

unset QML_SOURCES_PATHS

# Put the non-RUNPATH binaries back
mv "${appdir}/../findlib" "${appdir}/bin/findlib"

##########################################################################
# BUNDLE REMAINING DEPENDENCIES MANUALLY
##########################################################################

function find_library()
{
  # Print full path to a library or return exit status 1 if not found
  "${appdir}/bin/findlib" "$@"
}

function fallback_library()
{
  # Copy a library into a special fallback directory inside the AppDir.
  # Fallback libraries are not loaded at runtime by default, but they can
  # be loaded if it is found that the application would crash otherwise.
  local library="$1"
  local full_path="$(find_library "$1")"
  local new_path="${appdir}/fallback/${library}"
  mkdir -p "${new_path}" # directory has the same name as the library
  cp -L "${full_path}" "${new_path}/${library}"
  # Use the AppRun script to check at runtime whether the user has a copy of
  # this library. If not then add our copy's directory to $LD_LIBRARY_PATH.
}

# UNWANTED FILES
# linuxdeploy or linuxdeploy-plugin-qt may have added some files or folders
# that we don't want. List them here using paths relative to AppDir root.
# Report new additions at https://github.com/linuxdeploy/linuxdeploy/issues
# or https://github.com/linuxdeploy/linuxdeploy-plugin-qt/issues for Qt libs.
unwanted_files=(
  # none
)

# ADDITIONAL QT COMPONENTS
# linuxdeploy-plugin-qt may have missed some Qt files or folders that we need.
# List them here using paths relative to the Qt root directory. Report new
# additions at https://github.com/linuxdeploy/linuxdeploy-plugin-qt/issues
additional_qt_components=(
  /plugins/printsupport/libcupsprintersupport.so
)

# ADDITIONAL LIBRARIES
# linuxdeploy may have missed some libraries that we need
# Report new additions at https://github.com/linuxdeploy/linuxdeploy/issues
additional_libraries=(
  libssl.so.1.0.0    # OpenSSL (for Save Online)
  libcrypto.so.1.0.0 # OpenSSL (for Save Online)
)

# FALLBACK LIBRARIES
# These get bundled in the AppImage, but are only loaded if the user does not
# already have a version of the library installed on their system. This is
# helpful in cases where it is necessary to use a system library in order for
# a particular feature to work properly, but where the program would crash at
# startup if the library was not found. The fallback library may not provide
# the full functionality of the system version, but it does avoid the crash.
# Report new additions at https://github.com/linuxdeploy/linuxdeploy/issues
fallback_libraries=(
  libjack.so.0 # https://github.com/LMMS/lmms/pull/3958
)

for file in "${unwanted_files[@]}"; do
  rm -rf "${appdir}/${file}"
done

for file in "${additional_qt_components[@]}"; do
  mkdir -p "${appdir}/$(dirname "${file}")"
  cp -L "${QT_PATH}/${file}" "${appdir}/${file}"
done

for lib in "${additional_libraries[@]}"; do
  full_path="$(find_library "${lib}")"
  cp -L "${full_path}" "${appdir}/lib/${lib}"
done

for fb_lib in "${fallback_libraries[@]}"; do
  fallback_library "${fb_lib}"
done

# METHOD OF LAST RESORT
# Special treatment for some dependencies when all other methods fail

# Bundle libnss3 and friends as fallback libraries. Needed on Chromebook.
# See discussion at https://github.com/probonopd/linuxdeployqt/issues/35
#libnss3_files=(
#  # https://packages.ubuntu.com/xenial/amd64/libnss3/filelist
#  libnss3.so
#  libnssutil3.so
#  libsmime3.so
#  libssl3.so
#  nss/libfreebl3.chk
#  nss/libfreebl3.so
#  nss/libfreeblpriv3.chk
#  nss/libfreeblpriv3.so
#  nss/libnssckbi.so
#  nss/libnssdbm3.chk
#  nss/libnssdbm3.so
#  nss/libsoftokn3.chk
#  nss/libsoftokn3.so
#)

#libnss3_system_path="$(dirname "$(find_library libnss3.so)")"
#libnss3_appdir_path="${appdir}/fallback/libnss3.so" # directory named like library

#mkdir -p "${libnss3_appdir_path}/nss"

#for file in "${libnss3_files[@]}"; do
#  cp -L "${libnss3_system_path}/${file}" "${libnss3_appdir_path}/${file}"
#  rm -f "${appdir}/lib/$(basename "${file}")" # in case it was already packaged by linuxdeploy
#done

##########################################################################
# TURN APPDIR INTO AN APPIMAGE
##########################################################################

appimage="${appdir%.AppDir}.AppImage" # name to use for AppImage file

appimagetool_args=( # array
  # none
  )

created_files=(
  "${appimage}"
  )

if [[ "${UPDATE_INFORMATION}" ]]; then
  appimagetool_args+=( # append to array
    --updateinformation "${UPDATE_INFORMATION}"
    )
  created_files+=(
    "${appimage}.zsync" # this file will contain delta update data
    )
else
  cat >&2 <<EOF
$0: Automatic updates disabled.
To enable automatic updates, please set the env. variable UPDATE_INFORMATION
according to <https://github.com/AppImage/AppImageSpec/blob/master/draft.md>.
EOF
fi

# create AppImage
appimagetool "${appimagetool_args[@]}" "${appdir}" "${appimage}"

# We are running as root in the Docker image so all created files belong to
# root. Allow non-root users outside the Docker image to access these files.
chmod a+rwx "${created_files[@]}"
parent_dir="${PWD}"
while [[ "$(dirname "${parent_dir}")" != "${parent_dir}" ]]; do
  [[ "$parent_dir" == "/" ]] && break
  chmod a+rwx "$parent_dir"
  parent_dir="$(dirname "$parent_dir")"
done


ARTIFACTS_DIR=build.artifacts

BUILD_VERSION=$(cat ../$ARTIFACTS_DIR/env/build_version.env)
ARTIFACT_NAME=MuseScore-${BUILD_VERSION}-${ARCH}.AppImage

mv ${appimage} ../${ARTIFACTS_DIR}/${ARTIFACT_NAME}

cd ..

bash ./build/ci/tools/make_artifact_name_env.sh $ARTIFACT_NAME

echo "Package has finished!" 
