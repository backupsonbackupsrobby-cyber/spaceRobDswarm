pub struct PrecessionEpochMatrix {
    pub years_per_degree: u32,
    pub arcseconds_per_degree: u32,
    pub great_platonic_year: u32,
}
impl PrecessionEpochMatrix {
    pub fn load_celestial_baseline() -> Self {
        Self { years_per_degree: 72, arcseconds_per_degree: 3600, great_platonic_year: 25920 }
    }
    pub fn get_annual_degree_drift_constant(&self) -> f64 { 0.014 }
}
