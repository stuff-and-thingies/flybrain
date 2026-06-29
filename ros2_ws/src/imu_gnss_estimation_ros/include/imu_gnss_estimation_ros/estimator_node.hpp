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
    void odom_callback(px4_msgs::msg::VehicleOdometry::ConstSharedPtr msg);
    void imu_callback(px4_msgs::msg::SensorCombined::ConstSharedPtr msg);
    void gps_callback(px4_msgs::msg::SensorGps::ConstSharedPtr msg);

    void publish_odom(uint64_t px4_timestamp_us);

    void publish_viz_pose_and_path();

    static double px4_time_to_sec(uint64_t timestamp_us);

    imu_gnss_estimation_core::EkfConfig loadConfig();

    imu_gnss_estimation_core::BasicEkf ekf_;

    rclcpp::Subscription<px4_msgs::msg::VehicleOdometry>::SharedPtr odom_sub_;
    rclcpp::Subscription<px4_msgs::msg::SensorCombined>::SharedPtr imu_sub_;
    rclcpp::Subscription<px4_msgs::msg::SensorGps>::SharedPtr gps_sub_;

    rclcpp::Publisher<nav_msgs::msg::Odometry>::SharedPtr ekf_odom_pub_;
    rclcpp::Publisher<nav_msgs::msg::Path>::SharedPtr path_viz_pub_;
    rclcpp::Publisher<geometry_msgs::msg::PoseStamped>::SharedPtr pose_viz_pub_;

    nav_msgs::msg::Path path_msg_;
    std::size_t max_path_size_ = 3000;

    double gnss_vel_sigma_ = 0.3;
    bool initial_quaternion_acquired_ = false;

    std::optional<uint64_t> last_imu_timestamp_us_;
    std::optional<Eigen::Quaterniond> latest_quaternion_;
};
}  // namespace imu_gnss_estimation_ros
