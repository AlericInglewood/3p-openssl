#! /bin/sh

cd "`dirname "$0"`"
top="`pwd`"
stage="$top/stage"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

OPENSSL_SOURCE_DIR="openssl-git"

if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="`cygpath -u "$AUTOBUILD"`"
fi

# load autbuild provided shell functions and variables
set +x
eval "`"$AUTOBUILD" source_environment`"
set -x

build_unix()
{
    prefix="$1"
    target="$2"
    reltype="$3"
    shift; shift; shift

    # "shared" means build shared and static, instead of just static.
    ./Configure no-idea no-mdc2 no-rc5 no-gost enable-tlsext $* \
      --with-zlib-include="$stage/packages$prefix/include/zlib" --with-zlib-lib="$stage/packages$prefix/lib/release" \
      --prefix="$prefix" --libdir="lib/$reltype" $target

    make Makefile
    # Clean up stuff from a previous compile.
    make clean
    # Parallel building is broken for this package. Only use one core.
    make build_libs
    make build_apps
    make openssl.pc
    make libssl.pc
    make libcrypto.pc
    make INSTALL_PREFIX="$stage" install_sw

    # Fix the three pkgconfig files.
    find "$stage$prefix/lib/$reltype/pkgconfig" -type f -name '*.pc' -exec sed -i -e 's%'$prefix'%${PREBUILD_DIR}%g' {} \;

    if expr match "$*" '.* shared' >/dev/null; then
	# By default, 'make install' leaves even the user write bit off.
	# This causes trouble for us down the road, along about the time
	# the consuming build tries to strip libraries.
	chmod u+w "$stage$prefix/lib/$reltype"/libcrypto.so.* "$stage$prefix/lib/$reltype"/libssl.so.*
    fi
}

cd "$OPENSSL_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            load_vsvars

            # disable idea cypher per Phoenix's patent concerns (DEV-22827)
            perl Configure VC-WIN32 no-asm no-idea

            # Not using NASM
            ./ms/do_ms.bat

            nmake -f ms/ntdll.mak

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            cp "out32dll/libeay32.lib" "$stage/lib/debug"
            cp "out32dll/ssleay32.lib" "$stage/lib/debug"
            cp "out32dll/libeay32.lib" "$stage/lib/release"
            cp "out32dll/ssleay32.lib" "$stage/lib/release"

            cp out32dll/{libeay32,ssleay32}.dll "$stage/lib/debug"
            cp out32dll/{libeay32,ssleay32}.dll "$stage/lib/release"

            mkdir -p "$stage/include/openssl"

            # These files are symlinks in the SSL dist but just show up as text files
            # on windows that contain a string to their source.  So run some perl to
            # copy the right files over.
            perl ../copy-windows-links.pl "include/openssl" "$stage/include/openssl"
        ;;
        "darwin")
            build_unix /libraries/i686-linux darwin-i386-cc release no-shared
            build_unix /libraries/i686-linux debug-darwin-i386-cc debug no-shared
        ;;
        "linux")
            build_unix /libraries/i686-linux linux-generic32 release -fno-stack-protector threads no-shared
            build_unix /libraries/i686-linux debug-linux-generic32 debug -fno-stack-protector threads no-shared
        ;;
        "linux64")
            build_unix /libraries/x86_64-linux linux-x86_64 release -fno-stack-protector threads shared zlib-dynamic
            build_unix /libraries/x86_64-linux debug-linux-x86_64 debug -fno-stack-protector threads shared zlib-dynamic
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE "$stage/LICENSES/openssl.txt"
cd "$top"

pass

