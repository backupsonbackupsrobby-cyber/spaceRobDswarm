pub struct KuramotoCluster { pub total_nodes: usize, pub base_frequency_hz: f64, pub coupling_strength_k: f64, pub order_parameter_r: f64 }
impl KuramotoCluster {
    pub fn new() -> Self { Self { total_nodes: 72, base_frequency_hz: 40_000_000.0, coupling_strength_k: 0.15, order_parameter_r: 0.0 } }
}
