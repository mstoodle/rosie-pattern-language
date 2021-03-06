#!/bin/bash
echo "Creating script that sets GOPATH and ROSIE_HOME"
echo "export GOPATH=`pwd`" >setvars

LIB=`cd .. && pwd`
LUALIB=`cd ../../../submodules/lua/include && pwd`
RPEGLIB=`cd ../../../submodules/rosie-lpeg/src && pwd`

echo "Creating 'include' directory in 'src/rtest' and symlinks to librosie source"
mkdir -p src/rtest/include
ln -fs $LIB/librosie.h src/rtest/include/
ln -fs $LUALIB/luaxlib.h src/rtest/include/
ln -fs $RPEGLIB/rbuf.h src/rtest/include/
ln -fs $RPEGLIB/rpeg.h src/rtest/include/

echo "Linking librosie.a from librosie directory"
ln -fs $LIB/librosie.a src/rtest/librosie.a

echo "Creating link 'rosie' to rosie installation directory"
if [ -z $ROSIE_HOME ]; then
    ROSIE_HOME=`cd ../../.. && pwd`
    echo "ROSIE_HOME not set.  Assuming rosie installation is $ROSIE_HOME"
else
    echo "ROSIE_HOME is already set to: $ROSIE_HOME"
fi
ln -fs $ROSIE_HOME rosie


echo "--------------------------------------------------------"
echo "Use 'source setvars' to set GOPATH and ROSIE_HOME, then:"
echo "go build rtest"
echo "./rtest"






