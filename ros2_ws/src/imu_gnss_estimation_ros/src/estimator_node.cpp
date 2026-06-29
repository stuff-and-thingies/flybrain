#include "imu_gnss_estimation_ros/estimator_node.hpp"

namespace imu_gnss_estimation_ros
{

EstimatorNode::EstimatorNode()
    : Node("imu_gnss_estimator_node"), ekf_(loadConfig())
{
    odom_sub_ = this->create_subscription<px4_msgs::msg::VehicleOdometry>(
        "/fmu/out/vehicle_odometry", rclcpp::SensorDataQoS(),
        [this](px4_msgs::msg::VehicleOdometry::ConstSharedPtr msg)
        { this->odom_callback(msg); });

    imu_sub_ = this->create_subscription<px4_msgs::msg::SensorCombined>(
        "/fmu/out/sensor_combined", rclcpp::SensorDataQoS(),
        [this](px4_msgs::msg::SensorCombined::ConstSharedPtr msg)
        { this->imu_callback(msg); });

    gps_sub_ = this->create_subscription<px4_msgs::msg::SensorGps>(
        "/fmu/out/vehicle_gps_position", rclcpp::SensorDataQoS(),
        [this](px4_msgs::msg::SensorGps::ConstSharedPtr msg)
        { this->gps_callback(msg); });

    ekf_odom_pub_ = this->create_publisher<nav_msgs::msg::Odometry>(
        "/flybrain/ekf/odom_ned", 10);

    pose_viz_pub_ = this->create_publisher<geometry_msgs::msg::PoseStamped>(
        "/flybrain/ekf/pose_viz", 10);

    path_viz_pub_ = this->create_publisher<nav_msgs::msg::Path>(
        "/flybrain/ekf/path_viz", 10);

    path_msg_.header.frame_id = "ekf_viz";
};

imu_gnss_estimation_core::EkfConfig EstimatorNode::loadConfig()
{
    imu_gnss_estimation_core::EkfConfig config;

    this->declare_parameter("init_std_p", config.init_std_p);
    this->declare_parameter("init_std_v", config.init_std_v);
    this->declare_parameter("q_std_p", config.q_std_p);
    this->declare_parameter("q_std_v", config.q_std_v);
    this->declare_parameter("gnss_vel_sigma", config.gnss_vel_sigma);
    this->declare_parameter("add_gravity", config.add_gravity);

    config.init_std_p = this->get_parameter("init_std_p").as_double();
    config.init_std_v = this->get_parameter("init_std_v").as_double();
    config.q_std_p = this->get_parameter("q_std_p").as_double();
    config.q_std_v = this->get_parameter("q_std_v").as_double();
    config.gnss_vel_sigma = this->get_parameter("gnss_vel_sigma").as_double();
    config.add_gravity = this->get_parameter("add_gravity").as_bool();

    gnss_vel_sigma_ = config.gnss_vel_sigma;

    return config;
}

double EstimatorNode::px4_time_to_sec(uint64_t timestamp_us)
{
    return static_cast<double>(timestamp_us * 1.0e-6);
}

void EstimatorNode::odom_callback(
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

    imu_gnss_estimation_core::OdometrySample odom_sample;
    odom_sample.q_ned_body = q_ned_body;

    ekf_.store_quaternion_sample(odom_sample);
    initial_quaternion_acquired_ = true;
    latest_quaternion_ = q_ned_body;
}

void EstimatorNode::imu_callback(
    px4_msgs::msg::SensorCombined::ConstSharedPtr msg)
{
    if (!initial_quaternion_acquired_)
    {
        return;
    }

    if (!last_imu_timestamp_us_)
    {
        last_imu_timestamp_us_ = msg->timestamp;
        return;
    }

    const double dt =
        px4_time_to_sec(msg->timestamp - last_imu_timestamp_us_.value());

    last_imu_timestamp_us_ = msg->timestamp;

    imu_gnss_estimation_core::ImuAccelSample imu_sample;
    imu_sample.timestamp_s = px4_time_to_sec(msg->timestamp);
    imu_sample.accel_body_frd_mps2 =
        Eigen::Vector3d(static_cast<double>(msg->accelerometer_m_s2[0]),
                        static_cast<double>(msg->accelerometer_m_s2[1]),
                        static_cast<double>(msg->accelerometer_m_s2[2]));

    ekf_.predict_imu(imu_sample, dt);

    publish_odom(msg->timestamp);
}

void EstimatorNode::gps_callback(px4_msgs::msg::SensorGps::ConstSharedPtr msg)
{
    imu_gnss_estimation_core::GnssVelocitySample gnss_sample;

    gnss_sample.timestamp_s = px4_time_to_sec(msg->timestamp);

    gnss_sample.velocity_ned_mps =
        Eigen::Vector3d(static_cast<double>(msg->vel_n_m_s),
                        static_cast<double>(msg->vel_e_m_s),
                        static_cast<double>(msg->vel_d_m_s));

    gnss_sample.covariance =
        gnss_vel_sigma_ * gnss_vel_sigma_ * Eigen::Matrix3d::Identity();

    ekf_.update_gnss_velocity(gnss_sample);

    publish_odom(msg->timestamp);
}

void EstimatorNode::publish_odom(uint64_t px4_timestamp_us)
{
    const imu_gnss_estimation_core::StateVec& x = ekf_.state();
    const imu_gnss_estimation_core::StateMat& P = ekf_.covariance();

    nav_msgs::msg::Odometry msg;
    msg.header.stamp = this->get_clock()->now();
    msg.header.frame_id = "ned";
    msg.child_frame_id = "base_link_frd";

    msg.pose.pose.position.x = x(imu_gnss_estimation_core::StateIndex::PN);
    msg.pose.pose.position.y = x(imu_gnss_estimation_core::StateIndex::PE);
    msg.pose.pose.position.z = x(imu_gnss_estimation_core::StateIndex::PD);

    if (initial_quaternion_acquired_)
    {
        const Eigen::Quaterniond q = latest_quaternion_.value();
        msg.pose.pose.orientation.w = q.w();
        msg.pose.pose.orientation.x = q.x();
        msg.pose.pose.orientation.y = q.y();
        msg.pose.pose.orientation.z = q.z();
    }

    msg.twist.twist.linear.x = x(imu_gnss_estimation_core::StateIndex::VN);
    msg.twist.twist.linear.y = x(imu_gnss_estimation_core::StateIndex::VE);
    msg.twist.twist.linear.z = x(imu_gnss_estimation_core::StateIndex::VD);

    msg.pose.covariance[0] = P(0, 0);
    msg.pose.covariance[7] = P(1, 1);
    msg.pose.covariance[14] = P(2, 2);

    msg.twist.covariance[0] = P(3, 3);
    msg.twist.covariance[7] = P(4, 4);
    msg.twist.covariance[14] = P(5, 5);

    ekf_odom_pub_->publish(msg);

    publish_viz_pose_and_path();
}

void EstimatorNode::publish_viz_pose_and_path()
{
    const imu_gnss_estimation_core::StateVec& x = ekf_.state();

    geometry_msgs::msg::PoseStamped pose_msg;

    pose_msg.header.stamp = this->get_clock()->now();
    pose_msg.header.frame_id = "ekf_viz";

    pose_msg.pose.position.x = x(imu_gnss_estimation_core::StateIndex::PN);
    pose_msg.pose.position.y = x(imu_gnss_estimation_core::StateIndex::PE);
    pose_msg.pose.position.z = -x(imu_gnss_estimation_core::StateIndex::PD);

    pose_msg.pose.orientation.w = 1.0;
    pose_msg.pose.orientation.x = 0.0;
    pose_msg.pose.orientation.y = 0.0;
    pose_msg.pose.orientation.z = 0.0;

    pose_viz_pub_->publish(pose_msg);

    path_msg_.header.stamp = pose_msg.header.stamp;
    path_msg_.header.frame_id = "ekf_viz";
    path_msg_.poses.push_back(pose_msg);

    if (path_msg_.poses.size() > max_path_size_)
    {
        path_msg_.poses.erase(path_msg_.poses.begin());
    }

    path_viz_pub_->publish(path_msg_);
}

}  // namespace imu_gnss_estimation_ros
