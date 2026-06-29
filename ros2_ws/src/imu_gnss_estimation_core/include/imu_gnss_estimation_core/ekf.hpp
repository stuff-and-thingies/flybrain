#pragma once

#include "imu_gnss_estimation_core/samples.hpp"
#include "imu_gnss_estimation_core/types.hpp"

namespace imu_gnss_estimation_core
{

struct UpdateResult
{
    bool accepted = false;
    Eigen::Vector3d residual = Eigen::Vector3d::Zero();
};

struct EkfConfig
{
    double init_std_p = 1.0;  // initial position uncertainty per axis, m
    double init_std_v = 0.5;  // initial velocity uncertainty per axis, mps

    // process noise standard deviation, these are continuous time noise
    // densities. To get the actual variance value, they are squared first, then
    // multiplied by dt. Making it independent of update rate
    double q_std_p = 0.01;  // per position axis, m/sqrt(s)
    double q_std_v = 0.5;   // per velocity axis, (m/s)/sqrt(s)

    // uncertainty in gnss velocity measurement, m/s
    double gnss_vel_sigma = 0.3;

    bool add_gravity = true;
    double gravity_mps2 = 9.80665;
};

class BasicEkf
{
   public:
    explicit BasicEkf(const EkfConfig& config);

    void reset();

    void predict_imu(const ImuAccelSample& imu, double dt);

    UpdateResult update_gnss_velocity(const GnssVelocitySample& gnss);

    const StateVec& state() const;

    const StateMat& covariance() const;

   private:
    void _enforce_covariance_safety();

    UpdateResult _update_generic(const Eigen::VectorXd& residual,
                                 const Eigen::MatrixXd& H,
                                 const Eigen::MatrixXd& R);

   private:
    EkfConfig _config;

    StateVec _x;
    StateMat _P;
    bool _initialized;
};

}  // namespace imu_gnss_estimation_core
