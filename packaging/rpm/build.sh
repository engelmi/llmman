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

vendor_rust() {
    if [ -d "${PROJECT_ROOT}/vendor" ]; then
        echo "Rust vendor directory already exists, skipping"
        return
    fi
    if ! command -v cargo &>/dev/null; then
        echo "Warning: 'cargo' not found, skipping Rust crate vendoring"
        return
    fi
    echo "Vendoring Rust crate dependencies..."
    (cd "${PROJECT_ROOT}" && cargo vendor vendor)
    echo "Rust crates vendored"
}

vendor_go_shim() {
    if [ -d "${PROJECT_ROOT}/go-shim/vendor" ]; then
        echo "Go shim vendor directory already exists, skipping"
        return
    fi
    if ! command -v go &>/dev/null; then
        echo "Warning: 'go' not found, skipping Go module vendoring"
        echo "Note: The RPM build will require network access for Go modules"
        return
    fi
    echo "Vendoring Go module dependencies..."
    (cd "${PROJECT_ROOT}/go-shim" && go mod vendor)
    echo "Go modules vendored"
}

build_archive() {
    echo "Building source distribution for ${PACKAGE_NAME}-${VERSION}"

    generate_spec
    vendor_rust
    vendor_go_shim

    mkdir -p "${RPM_BUILD_DIR}"/{BUILD,RPMS,SPECS,SOURCES,SRPMS}

    local archive="${RPM_BUILD_DIR}/SOURCES/v${VERSION}.tar.gz"
    local tmp_tar="${RPM_BUILD_DIR}/tmp-${PACKAGE_NAME}-${VERSION}.tar"

    cd "${PROJECT_ROOT}"

    # Create base archive from tracked git content
    git archive \
        --format=tar \
        --prefix="${PACKAGE_NAME}-${VERSION}/" \
        HEAD > "${tmp_tar}"

    # Append untracked vendor/ (Rust crate dependencies)
    if [ -d vendor ]; then
        tar --append \
            --file="${tmp_tar}" \
            --transform "s|^|${PACKAGE_NAME}-${VERSION}/|" \
            vendor/
    fi

    # Append go-shim/vendor/ (Go module dependencies)
    if [ -d go-shim/vendor ]; then
        tar --append \
            --file="${tmp_tar}" \
            --transform "s|^|${PACKAGE_NAME}-${VERSION}/|" \
            go-shim/vendor/
    fi

    gzip -c "${tmp_tar}" > "${archive}"
    rm "${tmp_tar}"

    echo "${archive}"
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
