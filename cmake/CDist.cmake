# Pre-generated C distribution integration.
#
# When Nim is not available, or when MCF5407_USE_C_DIST is set, this file
# defines the targets `mcf5407_nim_objs`, `mcf5407` and `mcf5407::mcf5407`
# directly from the pre-generated C translation units in `c_src/`.

if(APPLE)
	set(MCF5407_PLATFORM "macos")
elseif(WIN32 OR CMAKE_SYSTEM_NAME STREQUAL "Windows")
	set(MCF5407_PLATFORM "windows_x86_64")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
	set(MCF5407_PLATFORM "linux_x86_64")
else()
	message(FATAL_ERROR
		"mcf5407: pre-generated C distribution does not support ${CMAKE_SYSTEM_NAME}.\n"
		"Supported platforms: macos, linux_x86_64, windows_x86_64.")
endif()

set(MCF5407_C_DIST_DIR "${PROJECT_SOURCE_DIR}/c_src/${MCF5407_PLATFORM}")
set(MCF5407_C_COMMON_DIR "${PROJECT_SOURCE_DIR}/c_src/common")

if(NOT EXISTS "${MCF5407_C_DIST_DIR}" OR NOT EXISTS "${MCF5407_C_COMMON_DIR}/nimbase.h")
	message(FATAL_ERROR
		"mcf5407: C distribution for ${MCF5407_PLATFORM} was not found at ${MCF5407_C_DIST_DIR}.\n"
		"Run tools/generate_c_dist.sh to generate it.")
endif()

file(GLOB MCF5407_C_SOURCES CONFIGURE_DEPENDS "${MCF5407_C_DIST_DIR}/*.c")
if(MCF5407_C_SOURCES STREQUAL "")
	message(FATAL_ERROR
		"mcf5407: no C translation units found in ${MCF5407_C_DIST_DIR}.")
endif()

message(STATUS
	"mcf5407: using pre-generated C distribution for ${MCF5407_PLATFORM} from ${MCF5407_C_DIST_DIR}")

# ---------------------------------------------------------------------------
# The OBJECT library.
#
# Compiled as C11 with warnings disarmed for generated code.
add_library(mcf5407_nim_objs OBJECT ${MCF5407_C_SOURCES})

target_include_directories(mcf5407_nim_objs SYSTEM PRIVATE
	"${MCF5407_C_COMMON_DIR}"
	"${MCF5407_C_DIST_DIR}")

target_compile_options(mcf5407_nim_objs PRIVATE
	"$<IF:$<C_COMPILER_ID:MSVC>,/WX-,-Wno-error>")

set_target_properties(mcf5407_nim_objs PROPERTIES
	C_STANDARD 11
	POSITION_INDEPENDENT_CODE ON)

set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads)
if(TARGET Threads::Threads)
	target_link_libraries(mcf5407_nim_objs PUBLIC Threads::Threads)
endif()

# ---------------------------------------------------------------------------
# The static library.
add_library(mcf5407 STATIC $<TARGET_OBJECTS:mcf5407_nim_objs>)

target_include_directories(mcf5407 PUBLIC
	"$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>")

if(TARGET Threads::Threads)
	target_link_libraries(mcf5407 PUBLIC Threads::Threads)
endif()

set_target_properties(mcf5407 PROPERTIES
	LINKER_LANGUAGE C)

# ---------------------------------------------------------------------------
# Exported alias for consumers.
add_library(mcf5407::mcf5407 ALIAS mcf5407)
add_library(coldfire::coldfire ALIAS mcf5407)
add_library(coldfire ALIAS mcf5407)

# ---------------------------------------------------------------------------
# Published ABI symbols for abi_smoke test.
set(MCF5407_ABI_GATE ON)
set(MCF5407_ABI_VISIBLE
	cf_runtime_init
	cf_create
	cf_destroy
	cf_reset
	cf_exec
	cf_set_reg
	cf_get_reg
	cf_halted
	cf_faulted
	cf_set_irq
	cf_state_size
	cf_state_save
	cf_state_load
	isp1181_create
	isp1181_destroy
	isp1181_read
	isp1181_write
	isp1181_rx
	isp1181_setup
	isp1181_in_token
	isp1181_set_backend
	isp1181_tick
	isp1181_log_written
	isp1181_log_retained
	isp1181_log_line
	isp1181_config_slots
	isp1181_config_slot
	isp1181_slot_buffer
	isp1181_report
	isp1181_state_size
	isp1181_state_save
	isp1181_state_load)
