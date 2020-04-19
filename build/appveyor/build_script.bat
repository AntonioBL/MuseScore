IF "%NIGHTLY_BUILD%" == "" (
  SET MSCORE_STABLE_BUILD="TRUE"
)

call C:\MuseScore\msvc_build.bat relwithdebinfo %TARGET_PROCESSOR_BITS% %APPVEYOR_BUILD_NUMBER%
call C:\MuseScore\msvc_build.bat installrelwithdebinfo %TARGET_PROCESSOR_BITS% %APPVEYOR_BUILD_NUMBER%

FOR %%I in (.) DO SET "BUILD_FOLDER=%%~nxI"

ECHO ON
ECHO Build folder = %BUILD_FOLDER%
