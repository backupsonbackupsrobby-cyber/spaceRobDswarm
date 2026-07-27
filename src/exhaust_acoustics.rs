// spaceRobDswarm Twin-Bank Acoustic Exhaust Module
// Calculating Straight-Through Gas Velocity and Sound Wave Attenuation

pub struct TrueDualExhaustEngine {
    pub hotdog_length_inches: f64,   // 21.0 inches per bank
    pub independent_banks: u8,       // 2 completely separated gas paths
    pub gas_velocity_limit_mps: f64, // Unrestricted volumetric flow baseline
}

impl TrueDualExhaustEngine {
    pub fn init_exhaust_bounds() -> Self {
        Self {
            hotdog_length_inches: 21.0,
            independent_banks: 2,
            gas_velocity_limit_mps: 85.0, // High-velocity gas extraction ceiling
        }
    }

    /// Calculates wave reflection attenuation factor across the 21-inch resonator core
    pub fn calculate_acoustic_damping(&self, frequency_hz: f64) -> f64 {
        if frequency_hz <= 0.0 { return 0.0; }
        // Length conversion: 21 inches = 0.5334 meters
        let length_meters = self.hotdog_length_inches * 0.0254;
        // Frequency-dependent damping curve optimized via our 0.052 wobble constant
        (frequency_hz * length_meters * 0.052).sqrt()
    }
}
