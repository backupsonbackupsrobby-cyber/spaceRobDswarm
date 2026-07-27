#[derive(Clone, Copy, Debug)]
pub struct State {
    pub value: f64,
}

#[derive(Clone, Copy, Debug)]
pub struct Drivers {
    pub shock: f64,
    pub pull: f64,
    pub tick: f64,
}

impl State {
    pub fn step(self, d: Drivers) -> State {
        State {
            value: self.value + d.shock + d.pull + d.tick,
        }
    }
}

pub fn shock_from_derivative(dphi_dt: f64, k_shock: f64) -> f64 {
    k_shock * dphi_dt
}

pub fn pull_from_error(error: f64, k_pull: f64) -> f64 {
    -k_pull * error
}

pub fn tick_from_clock(tau: f64, k_tick: f64, m: u32) -> f64 {
    let target = (m as f64) / 7200.0;
    if (tau - target).abs() < 1e-6 {
        k_tick
    } else {
        0.0
    }
}
