cmake_minimum_required(VERSION 3.24)
project(px4-opticalflow LANGUAGES CXX C)

option(BUILD_SHARED_LIBS "Build using shared libraries" ON)

find_package(OpenCV REQUIRED COMPONENTS core imgproc)

add_library(klt_feature_tracker klt-feature-tracker/src/trackFeatures.cpp)

target_include_directories(klt_feature_tracker PUBLIC 
    $<INSTALL_INTERFACE:klt_feature_tracker/include>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/klt-feature-tracker/include>    
)

target_link_libraries(klt_feature_tracker PUBLIC 
  opencv_core
)

add_library(px4_opticalflow
  src/optical_flow.cpp
  src/px4flow.cpp
  src/flow_px4.cpp
  src/flow_opencv.cpp
)

target_include_directories(px4_opticalflow PUBLIC 
    $<INSTALL_INTERFACE:include>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_link_libraries(px4_opticalflow PUBLIC klt_feature_tracker)


include(GNUInstallDirs)
install(TARGETS px4_opticalflow klt_feature_tracker
  EXPORT px4_opticalflowTargets
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
  PUBLIC_HEADER DESTINATION include
)

# NAMESPACE sets the namespace that your target will live within.
# you can have multiple targets under the same namespace
install(EXPORT px4_opticalflowTargets
  FILE px4_opticalflowTargets.cmake
  NAMESPACE px4_opticalflow::
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/px4_opticalflow
)

# this looks for your .cmake.in file that you created in step 1.
# if you set the directory differently you may need to handle this differently
include(CMakePackageConfigHelpers)
configure_package_config_file(${CMAKE_CURRENT_LIST_DIR}/cmake/px4_opticalflowConfig.cmake.in
  "${CMAKE_CURRENT_BINARY_DIR}/px4_opticalflowConfig.cmake"
  INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/px4_opticalflow
)

install(FILES
  "${CMAKE_CURRENT_BINARY_DIR}/px4_opticalflowConfig.cmake"
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/px4_opticalflow
)

# actually install your header files
install(
    DIRECTORY include/
    DESTINATION ${CMAKE_INSTALL_PREFIX}/include
    FILES_MATCHING PATTERN "*.h*"
    )

install(DIRECTORY 
    ${CMAKE_CURRENT_SOURCE_DIR}/klt-feature-tracker/include/
  DESTINATION 
    ${CMAKE_INSTALL_PREFIX}/klt-feature-tracker/include
)

install(DIRECTORY 
    ${CMAKE_CURRENT_SOURCE_DIR}/include/
  DESTINATION 
    ${CMAKE_INSTALL_PREFIX}/include
  FILES_MATCHING
    PATTERN "*.hpp"
)
