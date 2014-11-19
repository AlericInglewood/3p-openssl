#! /bin/sh

cd "`dirname "$0"`"
top="`pwd`"
stage="$top/stage"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

OPENSSL_VERSION="1.0.1c"
OPENSSL_SOURCE_DIR="openssl-$OPENSSL_VERSION"

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
    shift; shift

    # "shared" means build shared and static, instead of just static.
    ./Configure no-idea no-mdc2 no-rc5 no-gost enable-tlsext $* --prefix="$prefix" --libdir="lib/release" $target

    make Makefile
    # Parallel building is broken for this package. Only use one core.
    make build_libs
    make build_apps
    make openssl.pc
    make libssl.pc
    make libcrypto.pc
    make INSTALL_PREFIX="$stage" install_sw

    # Fix the three pkgconfig files.
    find "$stage$prefix/lib/release/pkgconfig" -type f -name '*.pc' -exec sed -i -e 's%'$prefix'%${PREBUILD_DIR}%g' {} \;

    # By default, 'make install' leaves even the user write bit off.
    # This causes trouble for us down the road, along about the time
    # the consuming build tries to strip libraries.
    chmod u+w "$stage$prefix/lib/release"/libcrypto.so.* "$stage$prefix/lib/release"/libssl.so.*
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
            build_unix /libraries/i686-linux debug-darwin-i386-cc no-shared
        ;;
        "linux")
            build_unix /libraries/i686-linux singu-linux-i386-i686/cmov -fno-stack-protector threads shared zlib-dynamic
        ;;
        "linux64")
            build_unix /libraries/x86_64-linux singu-linux-amd64 -fno-stack-protector threads shared zlib-dynamic
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE "$stage/LICENSES/openssl.txt"
cd "$top"

pass

