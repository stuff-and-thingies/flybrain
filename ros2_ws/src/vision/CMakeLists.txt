cmake_minimum_required(VERSION 3.8)
project(imu_gnss_estimation_ros)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# find dependencies
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(tf2 REQUIRED)
find_package(tf2_ros REQUIRED)

add_executable(estimator_node src/detector.cpp)

target_include_directories(estimator_node PRIVATE include)

ament_target_dependencies(
  rclcpp
  tf2_ros)

install(TARGETS estimator_node DESTINATION bin/imu_gnss_estimation_ros)

install(DIRECTORY config DESTINATION share/imu_gnss_estimation_ros)

ament_package()
