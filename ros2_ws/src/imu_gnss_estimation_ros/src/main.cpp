#include "imu_gnss_estimation_ros/estimator_node.hpp"
#include "rclcpp/rclcpp.hpp"

int main(int argc, char* argv[])
{
    rclcpp::init(argc, argv);

    auto node = std::make_shared<imu_gnss_estimation_ros::EstimatorNode>();

    rclcpp::spin(node);

    rclcpp::shutdown();

    return 0;
}
