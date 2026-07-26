pub struct InvariantMathMatrix {
    pub total_arcseconds: u32,
    pub total_degrees: f64,
    pub total_day_seconds: u32,
    pub system_wobble: f64,
    pub micro_sampling_tick: f64,
    pub macro_clock_step: f64,
    pub platonic_seed_034: f64,
    pub platonic_seed_052: f64,
    pub platonic_seed_075: f64,
    pub platonic_seed_150: f64,
}
impl InvariantMathMatrix {
    pub fn load_immutable_constants() -> Self {
        Self {
            total_arcseconds: 1_296_000,
            total_degrees: 3600.0,
            total_day_seconds: 86400,
            system_wobble: 0.052,
            micro_sampling_tick: 1.0 / 7200.0,
            macro_clock_step: 1.0 / 24.0,
            platonic_seed_034: 0.034,
            platonic_seed_052: 0.052,
            platonic_seed_075: 0.075,
            platonic_seed_150: 0.150,
        }
    }
}
