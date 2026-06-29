#pragma once

#include <Eigen/Dense>

namespace imu_gnss_estimation_core
{

struct ImuAccelSample
{
    double timestamp_s = 0.0;
    Eigen::Vector3d accel_body_frd_mps2 = Eigen::Vector3d::Zero();

    Eigen::Quaterniond q_ned_body = Eigen::Quaterniond::Identity();
};

struct GnssVelocitySample
{
    double timestamp_s = 0.0;

    Eigen::Vector3d velocity_ned_mps = Eigen::Vector3d::Zero();
    Eigen::Matrix3d covariance = Eigen::Matrix3d::Identity();
};

}  // namespace imu_gnss_estimation_core
