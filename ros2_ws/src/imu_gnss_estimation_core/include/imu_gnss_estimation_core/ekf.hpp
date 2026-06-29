#pragma once

#include "imu_gnss_estimation_core/config.hpp"
#include "imu_gnss_estimation_core/samples.hpp"
#include "imu_gnss_estimation_core/types.hpp"

namespace imu_gnss_estimation_core
{

struct UpdateResult
{
    bool accepted = false;
    Eigen::Vector3d residual = Eigen::Vector3d::Zero();
};

class BasicEkf
{
   public:
    explicit BasicEkf(const EkfConfig& config);

    void reset();

    void predict_imu(const ImuAccelSample& imu, double dt);

    UpdateResult update_gnss_velocity(const GnssVelocitySample& gnss);

    void store_quaternion_sample(const OdometrySample& odom);

    const StateVec& state() const;

    const StateMat& covariance() const;

   private:
    void enforce_covariance_safety();

    UpdateResult update_generic(const Eigen::VectorXd& residual,
                                const Eigen::MatrixXd& H,
                                const Eigen::MatrixXd& R);

    EkfConfig config_;

    StateVec x_;
    StateMat P_;
    bool initialized_ = false;

    Eigen::Quaterniond latest_quaternion_ = Eigen::Quaterniond::Identity();
};

}  // namespace imu_gnss_estimation_core
