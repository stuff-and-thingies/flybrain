#pragma once

#include <Eigen/Dense>

namespace imu_gnss_estimation_core
{

struct StateIndex
{
    static constexpr int PN = 0;
    static constexpr int PE = 1;
    static constexpr int PD = 2;
    static constexpr int VN = 3;
    static constexpr int VE = 4;
    static constexpr int VD = 5;

    static constexpr int SIZE = 6;
};

}  // namespace imu_gnss_estimation_core
