#include "imu_gnss_estimation_core/ekf.hpp"

namespace imu_gnss_estimation_core
{

BasicEkf::BasicEkf(const EkfConfig& config)
    : _config(config),
      _x(StateVec::Zero()),
      _P(StateMat::Zero()),
      _initialized(false)
{
    reset();
}

void BasicEkf::reset()
{
    _x.setZero();
    _P.setZero();

    _P(state_index::POS_N, state_index::POS_N) =
        _config.init_std_p * _config.init_std_p;
    _P(state_index::POS_E, state_index::POS_E) =
        _config.init_std_p * _config.init_std_p;
    _P(state_index::POS_D, state_index::POS_D) =
        _config.init_std_p * _config.init_std_p;
    _P(state_index::VEL_N, state_index::VEL_N) =
        _config.init_std_v * _config.init_std_v;
    _P(state_index::VEL_E, state_index::VEL_E) =
        _config.init_std_v * _config.init_std_v;
    _P(state_index::VEL_D, state_index::VEL_D) =
        _config.init_std_v * _config.init_std_v;

    _initialized = true;
}

void BasicEkf::predict_imu(const ImuAccelSample& imu, double dt)
{
    if (!_initialized)
    {
        return;
    }

    if (dt <= 0.0 || dt >= 0.1)
    {
        // bad dt or potential timeout
        return;
    }

    const Eigen::Matrix3d R_ned_body =
        imu.q_ned_body.normalized().toRotationMatrix();

    Eigen::Vector3d accel_ned = R_ned_body * imu.accel_body_frd_mps2;

    if (_config.add_gravity)
    {
        accel_ned(2) += _config.gravity_mps2;
    }

    _x(state_index::POS_N) +=
        _x(state_index::VEL_N) * dt + 0.5 * accel_ned(0) * dt * dt;
    _x(state_index::POS_E) +=
        _x(state_index::VEL_E) * dt + 0.5 * accel_ned(1) * dt * dt;
    _x(state_index::POS_D) +=
        _x(state_index::VEL_D) * dt + 0.5 * accel_ned(2) * dt * dt;

    _x(state_index::VEL_N) += accel_ned(0) * dt;
    _x(state_index::VEL_E) += accel_ned(1) * dt;
    _x(state_index::VEL_D) += accel_ned(2) * dt;

    StateMat F;
    F.setIdentity();
    F.block<3, 3>(state_index::POS_N, state_index::VEL_N) =
        Eigen::Matrix3d::Identity() * dt;

    StateMat Q;
    Q.setZero();

    const double qp2 = _config.q_std_p * _config.q_std_p;
    const double qv2 = _config.q_std_v * _config.q_std_v;

    Q(state_index::POS_N, state_index::POS_N) = qp2 * dt;
    Q(state_index::POS_E, state_index::POS_E) = qp2 * dt;
    Q(state_index::POS_D, state_index::POS_D) = qp2 * dt;

    Q(state_index::VEL_N, state_index::VEL_N) = qv2 * dt;
    Q(state_index::VEL_E, state_index::VEL_E) = qv2 * dt;
    Q(state_index::VEL_D, state_index::VEL_D) = qv2 * dt;

    _P = F * _P * F.transpose() + Q;

    _enforce_covariance_safety();
}

UpdateResult BasicEkf::update_gnss_velocity(const GnssVelocitySample& gnss)
{
    Eigen::Matrix<double, 3, state_index::SIZE> H;

    H.setZero();
    H.block<3, 3>(0, state_index::VEL_N) = Eigen::Matrix3d::Identity();

    const Eigen::Vector3d z = gnss.velocity_ned_mps;
    const Eigen::Vector3d h = _x.segment<3>(state_index::VEL_N);
    const Eigen::Vector3d r = z - h;

    return _update_generic(r, H, gnss.covariance);
}

void BasicEkf::_enforce_covariance_safety()
{
    // enforce symmetry
    _P = 0.5 * (_P + _P.transpose());

    // diagonal entires should be >= 0
    _P.diagonal() = _P.diagonal().cwiseMax(1e-9);

    // restrict diagonal entries from growing infinitely
    _P.diagonal() = _P.diagonal().cwiseMin(1e6);
}

UpdateResult BasicEkf::_update_generic(const Eigen::VectorXd& residual,
                                       const Eigen::MatrixXd& H,
                                       const Eigen::MatrixXd& R)
{
    UpdateResult result;

    if (!_initialized)
    {
        result.accepted = false;
        result.residual.setZero();
        return result;
    }

    Eigen::MatrixXd S = H * _P * H.transpose() + R;

    Eigen::MatrixXd K = _P * H.transpose() * S.inverse();

    Eigen::Vector<double, state_index::SIZE> correction = K * residual;

    _x += correction;

    StateMat I;
    I.setIdentity();

    _P = (I - K * H) * _P * (I - K * H).transpose() + K * R * K.transpose();

    _enforce_covariance_safety();

    result.residual = residual;
    result.accepted = true;

    return result;
}

const StateVec& BasicEkf::state() const { return _x; }

const StateMat& BasicEkf::covariance() const { return _P; }

}  // namespace imu_gnss_estimation_core
