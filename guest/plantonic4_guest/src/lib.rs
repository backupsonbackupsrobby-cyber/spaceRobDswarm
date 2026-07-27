#![no_std]

extern \"C\" {
    fn step(
        state_value: f64,
        dphi_dt: f64,
        error: f64,
        tau: f64,
        k_shock: f64,
        k_pull: f64,
        k_tick: f64,
        m: i32
    ) -> f64;
}

#[no_mangle]
pub extern \"C\" fn run_cycle(
    state_value: f64,
    dphi_dt: f64,
    error: f64,
    tau: f64,
    k_shock: f64,
    k_pull: f64,
    k_tick: f64,
    m: i32
) -> f64 {
    unsafe {
        step(
            state_value,
            dphi_dt,
            error,
            tau,
            k_shock,
            k_pull,
            k_tick,
            m
        )
    }
}
