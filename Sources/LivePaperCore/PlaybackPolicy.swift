import Foundation

public struct PlaybackEnvironment {
    public var onBattery: Bool
    public var lowPowerMode: Bool
    public var thermalPressure: Int // 0 nominal ... 3 critical
    public var processCPUPercent: Double

    public init(onBattery: Bool, lowPowerMode: Bool, thermalPressure: Int, processCPUPercent: Double) {
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.thermalPressure = thermalPressure
        self.processCPUPercent = processCPUPercent
    }
}

public enum PlaybackDirective: Equatable {
    case runNormal
    case runReducedRate(Double)
    case pause(String)
}

public struct PlaybackPolicy {
    public var maxCPUPercent: Double

    public init(maxCPUPercent: Double = 35.0) {
        self.maxCPUPercent = maxCPUPercent
    }

    public func evaluate(_ env: PlaybackEnvironment) -> PlaybackDirective {
        if env.thermalPressure >= 3 {
            return .pause("critical_thermal")
        }

        if env.lowPowerMode || env.onBattery {
            if env.processCPUPercent > maxCPUPercent {
                return .pause("power_cpu_budget")
            }
            return .runReducedRate(0.75)
        }

        if env.processCPUPercent > maxCPUPercent * 1.5 {
            return .runReducedRate(0.8)
        }

        return .runNormal
    }
}
