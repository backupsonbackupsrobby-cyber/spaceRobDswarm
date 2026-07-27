use wasmtime::Caller;
use crate::plantonic4::{
    State,
    Drivers,
    shock_from_derivative,
    pull_from_error,
    tick_from_clock
};

pub fn bind_plantonic4_to_wasm(linker: &mut wasmtime::Linker<()>) -> anyhow::Result<()> {
    linker.func_wrap(
        "plantonic4",
        "step",
        |_: Caller<'_, ()>,
         state_value: f64,
         dphi_dt: f64,
         error: f64,
         tau: f64,
         k_shock: f64,
         k_pull: f64,
         k_tick: f64,
         m: i32| -> f64 {

            let shock = shock_from_derivative(dphi_dt, k_shock);
            let pull  = pull_from_error(error, k_pull);
            let tick  = tick_from_clock(tau, k_tick, m as u32);

            let drivers = Drivers { shock, pull, tick };
            let state   = State { value: state_value };

            state.step(drivers).value
        }
    )?;

    Ok(())
}
