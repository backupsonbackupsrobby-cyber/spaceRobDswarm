// spaceRobDswarm Web3 Wallet Identity & Domain Minting Registry
// Resolves to: aiagency101.xyo

pub struct Web3IdentityMatrix {
    pub resolution_domain: &'static str,
    pub self_custody_wallet_1: &'static str, // Primary self-secured node
    pub self_custody_wallet_2: &'static str, // Secondary self-secured node
    pub custody_lite_wallet: &'static str,   // Network custody anchor node
    pub auto_mint_dns_on_chain: bool,
}

impl Web3IdentityMatrix {
    pub fn load_active_matrix() -> Self {
        Self {
            resolution_domain: "aiagency101.xyo",
            self_custody_wallet_1: "0x84CA4aFC3F395ebc0b519680B546Cd604C9c2018",
            self_custody_wallet_2: "0xabf4e0A237E4632b1740fdBe118162aA33b4F5aD",
            custody_lite_wallet:   "0x1AE2AF702063d304F8EBAC2153c91D79c62E381c",
            auto_mint_dns_on_chain: true,
        }
    }
}
