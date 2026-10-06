# Pre-generated C distribution integration.
#
# When Nim is not available, or when COLDFIRE_USE_C_DIST is set, this file
# defines the targets `coldfire_nim_objs`, `coldfire` and `coldfire::coldfire`
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
add_library(coldfire_nim_objs OBJECT ${MCF5407_C_SOURCES})

target_include_directories(coldfire_nim_objs SYSTEM PRIVATE
	"${MCF5407_C_COMMON_DIR}"
	"${MCF5407_C_DIST_DIR}")

target_compile_options(coldfire_nim_objs PRIVATE
	"$<IF:$<C_COMPILER_ID:MSVC>,/WX-,-Wno-error>")

set_target_properties(coldfire_nim_objs PROPERTIES
	C_STANDARD 11
	POSITION_INDEPENDENT_CODE ON)

set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads)
if(TARGET Threads::Threads)
	target_link_libraries(coldfire_nim_objs PUBLIC Threads::Threads)
endif()

# ---------------------------------------------------------------------------
# The static library.
add_library(coldfire STATIC $<TARGET_OBJECTS:coldfire_nim_objs>)

target_include_directories(coldfire PUBLIC
	"$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>")

if(TARGET Threads::Threads)
	target_link_libraries(coldfire PUBLIC Threads::Threads)
endif()

set_target_properties(coldfire PROPERTIES
	LINKER_LANGUAGE C)

# ---------------------------------------------------------------------------
# Exported alias for consumers.
add_library(coldfire::coldfire ALIAS coldfire)

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
	cf_state_load)
