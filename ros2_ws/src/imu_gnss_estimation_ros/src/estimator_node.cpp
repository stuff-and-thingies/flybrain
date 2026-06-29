#include "imu_gnss_estimation_ros/estimator_node.hpp"

namespace imu_gnss_estimation_ros
{

EstimatorNode::EstimatorNode()
    : Node("imu_gnss_estimator_node"), _ekf(_load_config())
{
    _odom_sub = this->create_subscription<px4_msgs::msg::VehicleOdometry>(
        "/fmu/out/vehicle_odometry", rclcpp::SensorDataQoS(),
        [this](px4_msgs::msg::VehicleOdometry::ConstSharedPtr msg)
        { this->_odom_callback(msg); });

    _imu_sub = this->create_subscription<px4_msgs::msg::SensorCombined>(
        "/fmu/out/sensor_combined", rclcpp::SensorDataQoS(),
        [this](px4_msgs::msg::SensorCombined::ConstSharedPtr msg)
        { this->_imu_callback(msg); });

    _gps_sub = this->create_subscription<px4_msgs::msg::SensorGps>(
        "/fmu/out/vehicle_gps_position", rclcpp::SensorDataQoS(),
        [this](px4_msgs::msg::SensorGps::ConstSharedPtr msg)
        { this->_gps_callback(msg); });

    _ekf_odom_pub = this->create_publisher<nav_msgs::msg::Odometry>(
        "/flybrain/ekf/odom_ned", 10);

    _pose_viz_pub = this->create_publisher<geometry_msgs::msg::PoseStamped>(
        "/flybrain/ekf/pose_viz", 10);

    _path_viz_pub = this->create_publisher<nav_msgs::msg::Path>(
        "/flybrain/ekf/path_viz", 10);

    _path_msg.header.frame_id = "ekf_viz";
};

imu_gnss_estimation_core::EkfConfig EstimatorNode::_load_config()
{
    imu_gnss_estimation_core::EkfConfig config;

    this->declare_parameter("init_std_p", config.init_std_p);
    this->declare_parameter("init_std_v", config.init_std_v);
    this->declare_parameter("q_std_p", config.q_std_p);
    this->declare_parameter("q_std_v", config.q_std_v);
    this->declare_parameter("gnss_vel_sigma", config.gnss_vel_sigma);
    this->declare_parameter("add_gravity", config.add_gravity);

    this->declare_parameter("max_path_size", static_cast<int>(3000));

    config.init_std_p = this->get_parameter("init_std_p").as_double();
    config.init_std_v = this->get_parameter("init_std_v").as_double();
    config.q_std_p = this->get_parameter("q_std_p").as_double();
    config.q_std_v = this->get_parameter("q_std_v").as_double();
    config.gnss_vel_sigma = this->get_parameter("gnss_vel_sigma").as_double();
    config.add_gravity = this->get_parameter("add_gravity").as_bool();

    config.gnss_vel_sigma = this->get_parameter("gnss_vel_sigma").as_double();

    _max_path_size = this->get_parameter("max_path_size").as_int();
    _gnss_vel_sigma = config.gnss_vel_sigma;

    return config;
}

double EstimatorNode::_px4_time_to_sec(uint64_t timestamp_us)
{
    return static_cast<double>(timestamp_us * 1.0e-6);
}

void EstimatorNode::_odom_callback(
    px4_msgs::msg::VehicleOdometry::ConstSharedPtr msg)
{
    const auto& q = msg->q;

    if (!std::isfinite(q[0]) || !std::isfinite(q[1]) || !std::isfinite(q[2]) ||
        !std::isfinite(q[3]))
    {
        return;
    }

    Eigen::Quaterniond q_ned_body(
        static_cast<double>(q[0]), static_cast<double>(q[1]),
        static_cast<double>(q[2]), static_cast<double>(q[3]));

    q_ned_body.normalize();

    _latest_quaternion = q_ned_body;
}

void EstimatorNode::_imu_callback(
    px4_msgs::msg::SensorCombined::ConstSharedPtr msg)
{
    if (!_latest_quaternion)
    {
        return;
    }

    if (!_last_imu_timestamp_us)
    {
        _last_imu_timestamp_us = msg->timestamp;
        return;
    }

    const double dt =
        _px4_time_to_sec(msg->timestamp - _last_imu_timestamp_us.value());

    _last_imu_timestamp_us = msg->timestamp;

    imu_gnss_estimation_core::ImuAccelSample imu_sample;
    imu_sample.timestamp_s = _px4_time_to_sec(msg->timestamp);
    imu_sample.accel_body_frd_mps2 =
        Eigen::Vector3d(static_cast<double>(msg->accelerometer_m_s2[0]),
                        static_cast<double>(msg->accelerometer_m_s2[1]),
                        static_cast<double>(msg->accelerometer_m_s2[2]));

    imu_sample.q_ned_body = _latest_quaternion.value();

    _ekf.predict_imu(imu_sample, dt);

    _publish_odom(msg->timestamp);
}

void EstimatorNode::_gps_callback(px4_msgs::msg::SensorGps::ConstSharedPtr msg)
{
    imu_gnss_estimation_core::GnssVelocitySample gnss_sample;

    gnss_sample.timestamp_s = _px4_time_to_sec(msg->timestamp);

    gnss_sample.velocity_ned_mps =
        Eigen::Vector3d(static_cast<double>(msg->vel_n_m_s),
                        static_cast<double>(msg->vel_e_m_s),
                        static_cast<double>(msg->vel_d_m_s));

    gnss_sample.covariance =
        _gnss_vel_sigma * _gnss_vel_sigma * Eigen::Matrix3d::Identity();

    _ekf.update_gnss_velocity(gnss_sample);

    _publish_odom(msg->timestamp);
}

void EstimatorNode::_publish_odom(uint64_t px4_timestamp_us)
{
    const imu_gnss_estimation_core::StateVec& x = _ekf.state();
    const imu_gnss_estimation_core::StateMat& P = _ekf.covariance();

    nav_msgs::msg::Odometry msg;
    msg.header.stamp = this->get_clock()->now();
    msg.header.frame_id = "ned";
    msg.child_frame_id = "base_link_frd";

    msg.pose.pose.position.x = x(imu_gnss_estimation_core::state_index::POS_N);
    msg.pose.pose.position.y = x(imu_gnss_estimation_core::state_index::POS_E);
    msg.pose.pose.position.z = x(imu_gnss_estimation_core::state_index::POS_D);

    if (_latest_quaternion)
    {
        const Eigen::Quaterniond q = _latest_quaternion.value();
        msg.pose.pose.orientation.w = q.w();
        msg.pose.pose.orientation.x = q.x();
        msg.pose.pose.orientation.y = q.y();
        msg.pose.pose.orientation.z = q.z();
    }

    msg.twist.twist.linear.x = x(imu_gnss_estimation_core::state_index::VEL_N);
    msg.twist.twist.linear.y = x(imu_gnss_estimation_core::state_index::VEL_E);
    msg.twist.twist.linear.z = x(imu_gnss_estimation_core::state_index::VEL_D);

    msg.pose.covariance[0] = P(0, 0);
    msg.pose.covariance[7] = P(1, 1);
    msg.pose.covariance[14] = P(2, 2);

    msg.twist.covariance[0] = P(3, 3);
    msg.twist.covariance[7] = P(4, 4);
    msg.twist.covariance[14] = P(5, 5);

    _ekf_odom_pub->publish(msg);

    _publish_viz_pose_and_path();
}

void EstimatorNode::_publish_viz_pose_and_path()
{
    const imu_gnss_estimation_core::StateVec& x = _ekf.state();

    geometry_msgs::msg::PoseStamped pose_msg;

    pose_msg.header.stamp = this->get_clock()->now();
    pose_msg.header.frame_id = "ekf_viz";

    pose_msg.pose.position.x = x(imu_gnss_estimation_core::state_index::POS_N);
    pose_msg.pose.position.y = x(imu_gnss_estimation_core::state_index::POS_E);
    pose_msg.pose.position.z = -x(imu_gnss_estimation_core::state_index::POS_D);

    pose_msg.pose.orientation.w = 1.0;
    pose_msg.pose.orientation.x = 0.0;
    pose_msg.pose.orientation.y = 0.0;
    pose_msg.pose.orientation.z = 0.0;

    _pose_viz_pub->publish(pose_msg);

    _path_msg.header.stamp = pose_msg.header.stamp;
    _path_msg.header.frame_id = "ekf_viz";
    _path_msg.poses.push_back(pose_msg);

    if (_path_msg.poses.size() > _max_path_size)
    {
        _path_msg.poses.erase(_path_msg.poses.begin());
    }

    _path_viz_pub->publish(_path_msg);
}

}  // namespace imu_gnss_estimation_ros
