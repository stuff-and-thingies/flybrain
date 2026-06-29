#pragma once

namespace imu_gnss_estimation_core
{

struct EkfConfig
{
    double init_std_p = 1.0;
    double init_std_v = 0.5;

    double q_std_p = 0.01;
    double q_std_v = 0.5;

    double gnss_vel_sigma = 0.3;

    bool add_gravity = true;
    double gravity_mps2 = 9.80665;
};

}  // namespace imu_gnss_estimation_core
