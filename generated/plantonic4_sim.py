import json
import math

def shock_from_derivative(dphi_dt, k_shock):
    return k_shock * dphi_dt

def pull_from_error(error, k_pull):
    return -k_pull * error

def tick_from_clock(tau, k_tick, m):
    target = m / 7200.0
    return k_tick if abs(tau - target) < 1e-6 else 0.0

def step(state_value, dphi_dt, error, tau, k_shock, k_pull, k_tick, m):
    shock = shock_from_derivative(dphi_dt, k_shock)
    pull  = pull_from_error(error, k_pull)
    tick  = tick_from_clock(tau, k_tick, m)
    return state_value + shock + pull + tick

def main():
    state = 0.0
    for m in range(1, 25):
        tau = m / 7200.0
        dphi_dt = math.sin(2 * math.pi * tau)
        error   = 0.01
        state   = step(state, dphi_dt, error, tau,
                       k_shock=1.0, k_pull=0.5, k_tick=0.1, m=m)
        print(json.dumps({"m": m, "tau": tau, "state": round(state, 6)}))

if __name__ == "__main__":
    main()
