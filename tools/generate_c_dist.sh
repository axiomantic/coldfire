#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v nim >/dev/null 2>&1; then
	echo "error: 'nim' executable was not found on PATH." >&2
	echo "The Nim compiler is required to generate the C distribution." >&2
	exit 1
fi

PIN_FILE="${REPO_ROOT}/.nim-version"
if [[ ! -f "${PIN_FILE}" ]]; then
	echo "error: ${PIN_FILE} does not exist." >&2
	exit 1
fi

PIN_VERSION="$(tr -d '[:space:]' < "${PIN_FILE}")"
INSTALLED_VERSION="$(nim --version | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"

if [[ "${INSTALLED_VERSION}" != "${PIN_VERSION}" ]]; then
	echo "error: Nim version does not match the pin." >&2
	echo "  pinned    : ${PIN_VERSION} (from ${PIN_FILE})" >&2
	echo "  installed : ${INSTALLED_VERSION}" >&2
	exit 1
fi

# Locate nimbase.h from nim dump or toolchain directory walk
NIM_LIB_DIR=""
DUMP_OUTPUT="$(nim dump --dump.format:json "${REPO_ROOT}/src/mcf5407.nim" 2>/dev/null || true)"
if [[ -n "${DUMP_OUTPUT}" ]]; then
	NIM_LIB_DIR="$(echo "${DUMP_OUTPUT}" | grep -oE '"libpath":"[^"]+"' | head -n 1 | cut -d'"' -f4 || true)"
fi

if [[ -z "${NIM_LIB_DIR}" || ! -f "${NIM_LIB_DIR}/nimbase.h" ]]; then
	NIM_EXE="$(command -v nim)"
	NIM_REAL="$(readlink -f "${NIM_EXE}" 2>/dev/null || python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${NIM_EXE}")"
	NIM_PREFIX="$(dirname "$(dirname "${NIM_REAL}")")"
	if [[ -f "${NIM_PREFIX}/lib/nimbase.h" ]]; then
		NIM_LIB_DIR="${NIM_PREFIX}/lib"
	fi
fi

if [[ -z "${NIM_LIB_DIR}" || ! -f "${NIM_LIB_DIR}/nimbase.h" ]]; then
	echo "error: nimbase.h could not be located." >&2
	exit 1
fi

# 1. Common headers
COMMON_DIR="${REPO_ROOT}/c_src/common"
mkdir -p "${COMMON_DIR}"
cp "${NIM_LIB_DIR}/nimbase.h" "${COMMON_DIR}/nimbase.h"
echo "Copied nimbase.h to ${COMMON_DIR}/nimbase.h"

# 2. macOS
MACOS_DIR="${REPO_ROOT}/c_src/macos"
rm -rf "${MACOS_DIR}"
mkdir -p "${MACOS_DIR}"
echo "Generating C distribution for macOS..."
nim c --compileOnly --noMain \
	--nimcache:"${MACOS_DIR}" \
	--path:"${REPO_ROOT}/src" \
	--mm:arc --panics:on -d:release \
	--cc:clang --os:macosx \
	--nimMainPrefix:mcf5407_ \
	--header:mcf5407_nim.h \
	"${REPO_ROOT}/src/mcf5407.nim"
rm -f "${MACOS_DIR}"/*.json

# 3. Linux x86_64
LINUX_DIR="${REPO_ROOT}/c_src/linux_x86_64"
rm -rf "${LINUX_DIR}"
mkdir -p "${LINUX_DIR}"
echo "Generating C distribution for Linux x86_64..."
nim c --compileOnly --noMain \
	--nimcache:"${LINUX_DIR}" \
	--path:"${REPO_ROOT}/src" \
	--mm:arc --panics:on -d:release \
	--cc:gcc --os:linux --cpu:amd64 \
	--nimMainPrefix:mcf5407_ \
	--header:mcf5407_nim.h \
	"${REPO_ROOT}/src/mcf5407.nim"
rm -f "${LINUX_DIR}"/*.json

# 4. Windows x86_64
WIN_DIR="${REPO_ROOT}/c_src/windows_x86_64"
rm -rf "${WIN_DIR}"
mkdir -p "${WIN_DIR}"
echo "Generating C distribution for Windows x86_64..."
nim c --compileOnly --noMain \
	--nimcache:"${WIN_DIR}" \
	--path:"${REPO_ROOT}/src" \
	--mm:arc --panics:on -d:release \
	--cc:vcc --os:windows --cpu:amd64 \
	--nimMainPrefix:mcf5407_ \
	--header:mcf5407_nim.h \
	"${REPO_ROOT}/src/mcf5407.nim"
rm -f "${WIN_DIR}"/*.json

echo "C distribution generated successfully in ${REPO_ROOT}/c_src"
