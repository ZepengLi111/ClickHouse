# KvikIO, the file IO layer cuDF reads Parquet and ORC through.
#
# Remote IO is left out: it wants libcurl, which ClickHouse does not carry in contrib, and
# ClickHouse has its own S3 and HTTP stack anyway. That drops the whole KvikIO_REMOTE_SUPPORT
# block - hdfs.cpp, remote_handle.cpp, shim/libcurl.cpp and detail/{multi_poll_reactor,
# remote_callback, tls, url}.cpp - so the list below is upstream's base set verbatim. cuFile (GPUDirect Storage) is also absent - KvikIO falls back to
# POSIX IO, which is what it does on any host without the cuFile driver.

if (NOT ENABLE_GPU)
    message (STATUS "Not using KvikIO")
    return ()
endif ()

set (KVIKIO_DIR "${ClickHouse_SOURCE_DIR}/contrib/kvikio/cpp")

add_library (_kvikio
    "${KVIKIO_DIR}/src/batch.cpp"
    "${KVIKIO_DIR}/src/bounce_buffer.cpp"
    "${KVIKIO_DIR}/src/buffer.cpp"
    "${KVIKIO_DIR}/src/compat_mode.cpp"
    "${KVIKIO_DIR}/src/compat_mode_manager.cpp"
    "${KVIKIO_DIR}/src/defaults.cpp"
    "${KVIKIO_DIR}/src/error.cpp"
    "${KVIKIO_DIR}/src/file_handle.cpp"
    "${KVIKIO_DIR}/src/file_utils.cpp"
    "${KVIKIO_DIR}/src/http_status_codes.cpp"
    "${KVIKIO_DIR}/src/logger.cpp"
    "${KVIKIO_DIR}/src/mmap.cpp"
    "${KVIKIO_DIR}/src/stream.cpp"
    "${KVIKIO_DIR}/src/utils.cpp"
    "${KVIKIO_DIR}/src/cufile/config.cpp"
    "${KVIKIO_DIR}/src/cufile/driver.cpp"
    "${KVIKIO_DIR}/src/detail/bounce_buffer_cache.cpp"
    "${KVIKIO_DIR}/src/detail/concurrent_request_limiter.cpp"
    "${KVIKIO_DIR}/src/detail/env.cpp"
    "${KVIKIO_DIR}/src/detail/event.cpp"
    "${KVIKIO_DIR}/src/detail/nvtx.cpp"
    "${KVIKIO_DIR}/src/detail/posix_io.cpp"
    "${KVIKIO_DIR}/src/detail/stream.cpp"
    "${KVIKIO_DIR}/src/detail/utils.cpp"
    "${KVIKIO_DIR}/src/shim/cuda.cpp"
    "${KVIKIO_DIR}/src/shim/cufile.cpp"
    "${KVIKIO_DIR}/src/shim/utils.cpp"
)

gpu_island_target (_kvikio)

# include/kvikio/logger_macros.hpp is checked in, generated from rapids-logger's template
# the way contrib/sz3-cmake keeps its version.hpp.
target_include_directories (_kvikio SYSTEM PUBLIC
    "${KVIKIO_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${GPU_CUDA_ROOT}/include"
)

# cufile.h is needed to compile even where GPUDirect Storage is unavailable: shim/cufile.hpp
# names cuFileBatchIOSetUp outside its own KVIKIO_CUFILE_FOUND guard. The library itself is
# dlopen'd at run time, so no cuFile library is linked here and KvikIO falls back to POSIX
# IO when the driver is missing.
target_compile_definitions (_kvikio
    PUBLIC KVIKIO_CUFILE_FOUND
    PRIVATE KVIKIO_LOG_ACTIVE_LEVEL=RAPIDS_LOGGER_LOG_LEVEL_INFO
)

# KVIKIO_CUFILE_VERSION_API_FOUND is a separate feature, not an implication of having
# cufile.h: upstream sets it only after `cuFileGetVersion` is found (cuFile 1.7, CUDA 12.2).
# Without it shim/cufile_h_wrapper.hpp declares the symbol itself and src/shim/cufile.cpp
# reports version 1070, so older cuFile headers keep working - defining it unconditionally
# would break them. Upstream probes with `try_compile`, which ClickHouse forbids (see
# cmake/block_build_time_checks.cmake), so the declaration is looked up in the very header
# that gets compiled - no compiler run, and the answer follows the toolchain in use.
set (KVIKIO_CUFILE_HEADER "${GPU_CUDA_ROOT}/include/cufile.h")
file (STRINGS "${KVIKIO_CUFILE_HEADER}" KVIKIO_CUFILE_VERSION_API_DECLARATION
    REGEX "CUfileError_t[ \t]+cuFileGetVersion[ \t]*\\(")
if (KVIKIO_CUFILE_VERSION_API_DECLARATION)
    message (STATUS "Using KvikIO with the cuFile version API")
    target_compile_definitions (_kvikio PUBLIC KVIKIO_CUFILE_VERSION_API_FOUND)
else ()
    message (STATUS "Using KvikIO without the cuFile version API: ${KVIKIO_CUFILE_HEADER} "
        "does not declare cuFileGetVersion, the cuFile version will be reported as 1070")
endif ()

target_link_libraries (_kvikio PUBLIC
    ch_contrib::cccl
    ch_contrib::rapids_logger
    ch_contrib::nvtx3
    ch_contrib::bs_thread_pool
    ch_gpu::cudart
)

add_library (ch_contrib::kvikio ALIAS _kvikio)
