cmake_minimum_required(VERSION 3.8)
project(imu_gnss_estimation_core)

# find dependencies
find_package(ament_cmake REQUIRED)
# uncomment the following section in order to fill in further dependencies
# manually. find_package(<dependency> REQUIRED)
find_package(Eigen3 REQUIRED)

add_library(imu_gnss_estimation_core src/ekf.cpp)

target_include_directories(
  imu_gnss_estimation_core
  PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
         $<INSTALL_INTERFACE:include>)

target_link_libraries(imu_gnss_estimation_core Eigen3::Eigen)

install(DIRECTORY include/ DESTINATION include)

install(
  TARGETS imu_gnss_estimation_core
  EXPORT export_imu_gnss_estimation_core
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)

ament_export_targets(export_imu_gnss_estimation_core HAS_LIBRARY_TARGET)
ament_export_dependencies(Eigen3)

ament_package()
