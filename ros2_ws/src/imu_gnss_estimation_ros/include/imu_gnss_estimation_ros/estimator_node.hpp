#pragma once

#include <optional>

#include "geometry_msgs/msg/pose_stamped.hpp"
#include "imu_gnss_estimation_core/ekf.hpp"
#include "nav_msgs/msg/odometry.hpp"
#include "nav_msgs/msg/path.hpp"
#include "px4_msgs/msg/sensor_combined.hpp"
#include "px4_msgs/msg/sensor_gps.hpp"
#include "px4_msgs/msg/vehicle_odometry.hpp"
#include "rclcpp/rclcpp.hpp"

namespace imu_gnss_estimation_ros
{
class EstimatorNode : public rclcpp::Node
{
   public:
    EstimatorNode();

   private:
    // member function
    void _odom_callback(px4_msgs::msg::VehicleOdometry::ConstSharedPtr msg);
    void _imu_callback(px4_msgs::msg::SensorCombined::ConstSharedPtr msg);
    void _gps_callback(px4_msgs::msg::SensorGps::ConstSharedPtr msg);

    void _publish_odom(uint64_t px4_timestamp_us);

    void _publish_viz_pose_and_path();

    static double _px4_time_to_sec(uint64_t timestamp_us);

    imu_gnss_estimation_core::EkfConfig _load_config();

   private:
    // member variables
    imu_gnss_estimation_core::BasicEkf _ekf;

    rclcpp::Subscription<px4_msgs::msg::VehicleOdometry>::SharedPtr _odom_sub;
    rclcpp::Subscription<px4_msgs::msg::SensorCombined>::SharedPtr _imu_sub;
    rclcpp::Subscription<px4_msgs::msg::SensorGps>::SharedPtr _gps_sub;

    rclcpp::Publisher<nav_msgs::msg::Odometry>::SharedPtr _ekf_odom_pub;
    rclcpp::Publisher<nav_msgs::msg::Path>::SharedPtr _path_viz_pub;
    rclcpp::Publisher<geometry_msgs::msg::PoseStamped>::SharedPtr _pose_viz_pub;

    nav_msgs::msg::Path _path_msg;
    std::size_t _max_path_size;

    double _gnss_vel_sigma;

    std::optional<uint64_t> _last_imu_timestamp_us;
    std::optional<Eigen::Quaterniond> _latest_quaternion;
};
}  // namespace imu_gnss_estimation_ros
