#!/bin/bash -e

PACKAGE_NAME="llmman"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PROJECT_ROOT="$(dirname $(dirname "$SCRIPT_DIR"))"
RPM_BUILD_DIR="${PROJECT_ROOT}/rpmbuild"

VERSION_SCRIPT="${PROJECT_ROOT}/packaging/version.sh"
VERSION="$($VERSION_SCRIPT)"
RELEASE=1

clean() {
    echo "Cleaning build artifacts..."
    rm -rf "${RPM_BUILD_DIR}"
    echo "Clean complete"
}

generate_spec() {
    echo "Generating spec file: Version=${VERSION} Release=${RELEASE}"

    sed \
        -e "s|@VERSION@|${VERSION}|g" \
        -e "s|@RELEASE@|${RELEASE}|g" \
        < "${PROJECT_ROOT}/packaging/rpm/${PACKAGE_NAME}.spec.in" \
        > "${PROJECT_ROOT}/packaging/rpm/${PACKAGE_NAME}.spec"
    
    echo "Generated ${PACKAGE_NAME}.spec"
}

build_archive() {
    echo "Building source distribution for ${PACKAGE_NAME}-${VERSION}"

    generate_pyproject
    generate_spec
    
    mkdir -p "${RPM_BUILD_DIR}"/{BUILD,RPMS,SPECS,SOURCES,SRPMS}
    cd "${PROJECT_ROOT}"

    git archive \
        --format=tar.gz \
        -o "${RPM_BUILD_DIR}"/SOURCES/llmman-"${VERSION}".tar.gz \
        --prefix=llmman-"${VERSION}"/ \
        --add-file=packaging/rpm/llmman.spec \
        HEAD
    
    echo "${BUILD_DIR}/${PACKAGE_NAME}-${VERSION}.tar.gz"
}

build_rpm() {
    local BUILD_ARG=$1

    build_archive
    generate_spec

    if [ "${SKIP_BUILDDEP}" != "yes" ]; then
        echo "Installing build dependencies..."
        dnf builddep -y "${PROJECT_ROOT}/packaging/rpm/${PACKAGE_NAME}.spec" || {
            echo "Warning: dnf builddep failed, continuing anyway..."
        }
    fi

    rpmbuild \
        --define "_topdir ${RPM_BUILD_DIR}" \
        -"${BUILD_ARG}" \
        "${PROJECT_ROOT}/packaging/rpm/${PACKAGE_NAME}.spec"
}

COMMAND=""
PRINT_SOURCE_PATH=false
USAGE="Usage: ${0} [--spec|--tar|--srpm|--rpm|--clean] [--psp]"
while [[ $# -gt 0 ]]; do
    case $1 in
        --spec)
            COMMAND="generate_spec"
            shift
            ;;
        --tar)
            COMMAND="build_archive"
            shift
            ;;
        --srpm)
            BUILD_ARG="bs"
            COMMAND="build_rpm $BUILD_ARG"
            shift
            ;;
        --rpm)
            BUILD_ARG="ba"
            COMMAND="build_rpm $BUILD_ARG"
            shift
            ;;
        --clean)
            COMMAND="clean"
            shift
            ;;
        --psp|--print-source-path)
            PRINT_SOURCE_PATH=true
            shift
            ;;
        -h|--help)
            echo "$USAGE"
            exit 0
            ;;
        -*|--*)
            echo "Unknown option $1"
            echo "$USAGE"
            exit 1
            ;;
        *)
            echo "Unknown positional argument: $1"
            echo "$USAGE"
            exit 1
            ;;
    esac
done

if [ -z "${COMMAND}" ]; then
    echo "No command given"
    echo "${USAGE}"
    exit 1
fi

$COMMAND

exit 0
