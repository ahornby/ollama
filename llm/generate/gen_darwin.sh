#!/bin/bash
# This script is intended to run inside the go generate
# working directory must be ./llm/generate/

# TODO - add hardening to detect missing tools (cmake, etc.)

set -ex
set -o pipefail
echo "Starting darwin generate script"
source $(dirname $0)/gen_common.sh
init_vars
git_module_setup
apply_patches

sign() {
    if [ -n "$APPLE_IDENTITY" ]; then
        codesign -f --timestamp --deep --options=runtime --sign "$APPLE_IDENTITY" --identifier ai.ollama.ollama $1
    fi
}

COMMON_DARWIN_DEFS="-DBUILD_SHARED_LIBS=off -DCMAKE_OSX_DEPLOYMENT_TARGET=11.3 -DLLAMA_METAL_MACOSX_VERSION_MIN=11.3 -DCMAKE_SYSTEM_NAME=Darwin -DGGML_METAL_EMBED_LIBRARY=on -DGGML_OPENMP=off"

case "${GOARCH}" in
"amd64")
    COMMON_CPU_DEFS="${COMMON_DARWIN_DEFS} -DCMAKE_SYSTEM_PROCESSOR=${ARCH} -DCMAKE_OSX_ARCHITECTURES=${ARCH} -DGGML_METAL=off -DGGML_NATIVE=off"

    # Static build for linking into the Go binary
    if [ -z "${OLLAMA_SKIP_STATIC_GENERATE}" -o "${OLLAMA_CPU_TARGET}" = "static" ]; then
        init_vars
        CMAKE_TARGETS="--target llama --target ggml"
        CMAKE_DEFS="${COMMON_CPU_DEFS} -DGGML_BLAS=off -DGGML_ACCELERATE=off -DGGML_AVX=off -DGGML_AVX2=off -DGGML_AVX512=off -DGGML_FMA=off -DGGML_F16C=off ${CMAKE_DEFS}"
        BUILD_DIR="../build/darwin/${ARCH}_static"
        echo "Building static library"
        build
    fi

    if [ -z "$OLLAMA_SKIP_CPU_GENERATE" ]; then
        #
        # CPU first for the default library, set up as lowest common denominator for maximum compatibility (including Rosetta)
        #
        init_vars
        CMAKE_DEFS="${COMMON_CPU_DEFS} -DGGML_ACCELERATE=off -DGGML_BLAS=off -DGGML_AVX=off -DGGML_AVX2=off -DGGML_AVX512=off -DGGML_FMA=off -DGGML_F16C=off ${CMAKE_DEFS}"
        BUILD_DIR="../build/darwin/${ARCH}/cpu"
        echo "Building LCD CPU"
        build
        sign ${BUILD_DIR}/bin/ollama_llama_server
        compress

        #
        # ~2011 CPU Dynamic library with more capabilities turned on to optimize performance
        # Approximately 400% faster than LCD on same CPU
        #
        init_vars
        CMAKE_DEFS="${COMMON_CPU_DEFS} -DGGML_ACCELERATE=off -DGGML_BLAS=off -DGGML_AVX=on -DGGML_AVX2=off -DGGML_AVX512=off -DGGML_FMA=off -DGGML_F16C=off ${CMAKE_DEFS}"
        BUILD_DIR="../build/darwin/${ARCH}/cpu_avx"
        echo "Building AVX CPU"
        build
        sign ${BUILD_DIR}/bin/ollama_llama_server
        compress

        #
        # ~2013 CPU Dynamic library
        # Approximately 10% faster than AVX on same CPU
        #
        init_vars
        CMAKE_DEFS="${COMMON_CPU_DEFS} -DGGML_ACCELERATE=on -DGGML_BLAS=off -DGGML_AVX=on -DGGML_AVX2=on -DGGML_AVX512=off -DGGML_FMA=on -DGGML_F16C=on ${CMAKE_DEFS}"
        BUILD_DIR="../build/darwin/${ARCH}/cpu_avx2"
        echo "Building AVX2 CPU"
        EXTRA_LIBS="${EXTRA_LIBS} -framework Accelerate -framework Foundation"
        build
        sign ${BUILD_DIR}/bin/ollama_llama_server
        compress
    fi

    if [ -z "$OLLAMA_SKIP_METAL_GENERATE" ]; then
        init_vars
        CMAKE_DEFS="${COMMON_DARWIN_DEFS} -DCMAKE_SYSTEM_PROCESSOR=${ARCH} -DCMAKE_OSX_ARCHITECTURES=${ARCH} ${CMAKE_DEFS}"
        CMAKE_DEFS="${COMMON_CPU_DEFS} -DGGML_METAL=on -DGGML_ACCELERATE=on -DGGML_AVX=on -DGGML_AVX2=on -DGGML_AVX512=off -DGGML_FMA=on ${CMAKE_DEFS}"
        BUILD_DIR="../build/darwin/${ARCH}/metal"
        echo "Building metal GPU"
        EXTRA_LIBS="${EXTRA_LIBS} -framework Accelerate -framework Foundation -framework Metal -framework MetalKit -framework MetalPerformanceShaders"
        build
        sign ${BUILD_DIR}/bin/ollama_llama_server
        compress
    fi

    # do "brew install vulkan-tools glslang molkten-vk" to get necessary tools
    if [ -z "$MOLTEN_VK_PATH" ] && brew --prefix molten-vk; then
        MAYBE_MOLTEN_VK_PATH=$(brew --prefix molten-vk)
        if [ -r "${MAYBE_MOLTEN_VK_PATH}/lib/libMoltenVK.dylib" ]; then
            MOLTEN_VK_PATH="$MAYBE_MOLTEN_VK_PATH"
        fi
    fi

    if [[ -z "${OLLAMA_SKIP_VULKAN_GENERATE}" && -n "${MOLTEN_VK_PATH}" ]]; then
        echo "MoltenVK libraries detected - building dynamic vulkan library"
        init_vars
        CMAKE_DEFS="${COMMON_CPU_DEFS} -DGGML_VULKAN=on -DGGML_ACCELERATE=on -DGGML_AVX=on -DGGML_AVX2=on -DGGML_AVX512=off -DGGML_FMA=on ${CMAKE_DEFS}"
        BUILD_DIR="../build/darwin/${ARCH}/vulkan"
        echo "Building MoltenVK vulkan GPU"
        # EXTRA_LIBS="-L${MOLTEN_VK_PATH}/lib -llibMoltenVK"
        EXTRA_LIBS="${EXTRA_LIBS} -framework Accelerate -framework Foundation -framework MolktenVK"
        build
        sign "${BUILD_DIR}/bin/ollama_llama_server"
        compress
    fi
    exit 1

    ;;
"arm64")

    # Static build for linking into the Go binary
    init_vars
    CMAKE_TARGETS="--target llama --target ggml"
    CMAKE_DEFS="${COMMON_DARWIN_DEFS} -DCMAKE_OSX_DEPLOYMENT_TARGET=11.3 -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR=${ARCH} -DCMAKE_OSX_ARCHITECTURES=${ARCH} ${CMAKE_DEFS}"
    BUILD_DIR="../build/darwin/${ARCH}_static"
    echo "Building static library"
    build

    if [ -z "$OLLAMA_SKIP_METAL_GENERATE" ]; then
        init_vars
        CMAKE_DEFS="${COMMON_DARWIN_DEFS} -DCMAKE_SYSTEM_PROCESSOR=${ARCH} -DCMAKE_OSX_ARCHITECTURES=${ARCH} ${CMAKE_DEFS}"
        BUILD_DIR="../build/darwin/${ARCH}/metal"
        EXTRA_LIBS="${EXTRA_LIBS} -framework Accelerate -framework Foundation -framework Metal -framework MetalKit -framework MetalPerformanceShaders"
        build
        sign ${BUILD_DIR}/bin/ollama_llama_server
        compress
    fi
    ;;
*)
    echo "GOARCH must be set"
    echo "this script is meant to be run from within go generate"
    exit 1
    ;;
esac

cleanup
echo "go generate completed.  LLM runners: $(cd ${BUILD_DIR}/..; echo *)"
